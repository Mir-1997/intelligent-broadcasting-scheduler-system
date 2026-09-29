"""Firestore-backed repository.

Collections (each optionally prefixed by ``COLLECTION_PREFIX``)::

    admin/default            the single admin document
    packages/{package_id}    Package
    riders/{rider_id}        Rider
    assignments/{asg_id}     Assignment

Pairing runs inside a Firestore transaction: the query for candidates is a transactional
read, so if another request assigns the same rider/package before we commit, Firestore
aborts and retries our transaction with fresh data. No rider is ever double-assigned.
"""

import logging
import os
from enum import Enum
from typing import Any

from google.cloud.firestore import AsyncClient, AsyncTransaction, FieldFilter, Query
from google.cloud.firestore_v1.async_transaction import async_transactional
from google.oauth2 import service_account
from pydantic import BaseModel

from broadcast_scheduler.config import Settings
from broadcast_scheduler.exceptions import ConflictError, NotFoundError
from broadcast_scheduler.matching import nearest_package, nearest_rider, pair
from broadcast_scheduler.models import (
    Admin,
    Assignment,
    MatchTrigger,
    Package,
    PackageStatus,
    Rider,
    RiderStatus,
    utc_now,
)

logger = logging.getLogger(__name__)

_DELETE_BATCH_SIZE = 400  # Firestore allows 500 writes per batch


def _to_doc(model: BaseModel) -> dict[str, Any]:
    """Pydantic -> Firestore. Keeps datetimes as native Timestamps, flattens enums."""

    def convert(value: Any) -> Any:
        if isinstance(value, Enum):
            return value.value
        if isinstance(value, dict):
            return {k: convert(v) for k, v in value.items()}
        if isinstance(value, list):
            return [convert(v) for v in value]
        return value

    return convert(model.model_dump(mode="python"))


def create_firestore_client(settings: Settings) -> AsyncClient:
    """Build an AsyncClient pointed at the emulator or a real project, per settings.

    The key file is loaded explicitly because values from ``.env`` never reach
    ``os.environ``, which is where the Google libraries look for credentials.
    """
    if settings.firestore_emulator_host:
        os.environ["FIRESTORE_EMULATOR_HOST"] = settings.firestore_emulator_host
        credentials = None
    else:
        os.environ.pop("FIRESTORE_EMULATOR_HOST", None)
        credentials = (
            service_account.Credentials.from_service_account_file(
                settings.google_application_credentials
            )
            if settings.google_application_credentials
            else None  # Application Default Credentials
        )
    logger.info(
        "Firestore: %s, project=%s, database=%s, collection_prefix=%r",
        f"emulator at {settings.firestore_emulator_host}"
        if settings.firestore_emulator_host
        else "REAL project",
        settings.gcp_project_id,
        settings.firestore_database,
        settings.collection_prefix,
    )
    return AsyncClient(
        project=settings.gcp_project_id,
        credentials=credentials,
        database=settings.firestore_database,
    )


class FirestoreSchedulerRepository:
    def __init__(self, client: AsyncClient, collection_prefix: str = "") -> None:
        self._client = client
        self._admin = client.collection(f"{collection_prefix}admin").document("default")
        self._packages = client.collection(f"{collection_prefix}packages")
        self._riders = client.collection(f"{collection_prefix}riders")
        self._assignments = client.collection(f"{collection_prefix}assignments")

    # --- admin ---------------------------------------------------------------------------

    async def get_admin(self) -> Admin | None:
        snapshot = await self._admin.get()
        return Admin.model_validate(snapshot.to_dict()) if snapshot.exists else None

    async def save_admin(self, admin: Admin) -> Admin:
        await self._admin.set(_to_doc(admin))
        return admin

    # --- matching ------------------------------------------------------------------------

    async def add_package(
        self, package: Package, max_radius_miles: float
    ) -> tuple[Package, Assignment | None]:
        @async_transactional
        async def run(tx: AsyncTransaction) -> tuple[Package, Assignment | None]:
            query = self._riders.where(
                filter=FieldFilter("status", "==", RiderStatus.AVAILABLE.value)
            )
            riders = [Rider.model_validate(s.to_dict()) async for s in await tx.get(query)]
            match = nearest_rider(package, riders, max_radius_miles)
            if match is None:
                tx.create(self._packages.document(package.id), _to_doc(package))
                return package, None
            rider, distance = match
            stored, rider, assignment = pair(
                package, rider, distance, MatchTrigger.PACKAGE_ADDED, utc_now()
            )
            self._write_pair(tx, stored, rider, assignment, new_package=True)
            return stored, assignment

        return await run(self._client.transaction())

    async def add_rider(
        self, rider: Rider, max_radius_miles: float
    ) -> tuple[Rider, Assignment | None]:
        @async_transactional
        async def run(tx: AsyncTransaction) -> tuple[Rider, Assignment | None]:
            query = self._packages.where(
                filter=FieldFilter("status", "==", PackageStatus.WAITING.value)
            )
            packages = [Package.model_validate(s.to_dict()) async for s in await tx.get(query)]
            match = nearest_package(rider, packages, max_radius_miles)
            if match is None:
                tx.create(self._riders.document(rider.id), _to_doc(rider))
                return rider, None
            package, distance = match
            package, stored, assignment = pair(
                package, rider, distance, MatchTrigger.RIDER_ADDED, utc_now()
            )
            self._write_pair(tx, package, stored, assignment, new_package=False)
            return stored, assignment

        return await run(self._client.transaction())

    def _write_pair(
        self,
        tx: AsyncTransaction,
        package: Package,
        rider: Rider,
        assignment: Assignment,
        *,
        new_package: bool,
    ) -> None:
        """Queue the three writes of a pairing. The newly-arrived side is created, the
        existing side is updated (which fails the transaction if it vanished meanwhile)."""
        package_ref = self._packages.document(package.id)
        rider_ref = self._riders.document(rider.id)
        if new_package:
            tx.create(package_ref, _to_doc(package))
            tx.update(rider_ref, _assignment_fields(rider))
        else:
            tx.create(rider_ref, _to_doc(rider))
            tx.update(package_ref, _assignment_fields(package))
        tx.create(self._assignments.document(assignment.id), _to_doc(assignment))

    # --- packages ------------------------------------------------------------------------

    async def get_package(self, package_id: str) -> Package | None:
        snapshot = await self._packages.document(package_id).get()
        return Package.model_validate(snapshot.to_dict()) if snapshot.exists else None

    async def list_packages(self, status: PackageStatus | None = None) -> list[Package]:
        query = self._packages
        if status is not None:
            query = query.where(filter=FieldFilter("status", "==", status.value))
        # Sorted client-side: ordering on another field than the filter would need a
        # composite index in production Firestore.
        items = [Package.model_validate(s.to_dict()) async for s in query.stream()]
        return sorted(items, key=lambda p: p.created_at)

    async def delete_package(self, package_id: str) -> Package:
        ref = self._packages.document(package_id)

        @async_transactional
        async def run(tx: AsyncTransaction) -> Package:
            snapshot = await ref.get(transaction=tx)
            if not snapshot.exists:
                raise NotFoundError(f"Package {package_id} not found")
            package = Package.model_validate(snapshot.to_dict())
            if package.status != PackageStatus.WAITING:
                raise ConflictError(f"Package {package_id} is already assigned")
            tx.delete(ref)
            return package

        return await run(self._client.transaction())

    # --- riders --------------------------------------------------------------------------

    async def get_rider(self, rider_id: str) -> Rider | None:
        snapshot = await self._riders.document(rider_id).get()
        return Rider.model_validate(snapshot.to_dict()) if snapshot.exists else None

    async def list_riders(self, status: RiderStatus | None = None) -> list[Rider]:
        query = self._riders
        if status is not None:
            query = query.where(filter=FieldFilter("status", "==", status.value))
        items = [Rider.model_validate(s.to_dict()) async for s in query.stream()]
        return sorted(items, key=lambda r: r.created_at)

    async def delete_rider(self, rider_id: str) -> Rider:
        ref = self._riders.document(rider_id)

        @async_transactional
        async def run(tx: AsyncTransaction) -> Rider:
            snapshot = await ref.get(transaction=tx)
            if not snapshot.exists:
                raise NotFoundError(f"Rider {rider_id} not found")
            rider = Rider.model_validate(snapshot.to_dict())
            if rider.status != RiderStatus.AVAILABLE:
                raise ConflictError(f"Rider {rider_id} is already assigned")
            tx.delete(ref)
            return rider

        return await run(self._client.transaction())

    # --- assignments / maintenance -------------------------------------------------------

    async def list_assignments(self, limit: int = 50) -> list[Assignment]:
        query = self._assignments.order_by("created_at", direction=Query.DESCENDING).limit(limit)
        return [Assignment.model_validate(s.to_dict()) async for s in query.stream()]

    async def reset(self) -> None:
        for collection in (self._packages, self._riders, self._assignments):
            while True:
                docs = [d async for d in collection.limit(_DELETE_BATCH_SIZE).stream()]
                if not docs:
                    break
                batch = self._client.batch()
                for doc in docs:
                    batch.delete(doc.reference)
                await batch.commit()

    async def close(self) -> None:
        self._client.close()


def _assignment_fields(entity: Package | Rider) -> dict[str, Any]:
    """The subset of fields that change when an existing entity gets paired."""
    doc = _to_doc(entity)
    keys = (
        ("status", "assigned_rider_id", "assigned_at")
        if isinstance(entity, Package)
        else ("status", "assigned_package_id", "assigned_at")
    )
    return {k: doc[k] for k in keys}
