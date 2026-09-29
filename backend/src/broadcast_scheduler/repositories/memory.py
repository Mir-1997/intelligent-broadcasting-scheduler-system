"""In-process repository. Used by the test-suite and by ``STORAGE_BACKEND=memory``."""

import asyncio

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


class InMemorySchedulerRepository:
    """Dictionary-backed store. A single lock gives the same atomicity as a transaction."""

    def __init__(self) -> None:
        self._admin: Admin | None = None
        self._packages: dict[str, Package] = {}
        self._riders: dict[str, Rider] = {}
        self._assignments: dict[str, Assignment] = {}
        self._lock = asyncio.Lock()

    async def get_admin(self) -> Admin | None:
        return self._admin

    async def save_admin(self, admin: Admin) -> Admin:
        self._admin = admin
        return admin

    async def add_package(
        self, package: Package, max_radius_miles: float
    ) -> tuple[Package, Assignment | None]:
        async with self._lock:
            match = nearest_rider(package, list(self._riders.values()), max_radius_miles)
            if match is None:
                self._packages[package.id] = package
                return package, None
            rider, distance = match
            package, rider, assignment = pair(
                package, rider, distance, MatchTrigger.PACKAGE_ADDED, utc_now()
            )
            self._store_pair(package, rider, assignment)
            return package, assignment

    async def add_rider(
        self, rider: Rider, max_radius_miles: float
    ) -> tuple[Rider, Assignment | None]:
        async with self._lock:
            match = nearest_package(rider, list(self._packages.values()), max_radius_miles)
            if match is None:
                self._riders[rider.id] = rider
                return rider, None
            package, distance = match
            package, rider, assignment = pair(
                package, rider, distance, MatchTrigger.RIDER_ADDED, utc_now()
            )
            self._store_pair(package, rider, assignment)
            return rider, assignment

    def _store_pair(self, package: Package, rider: Rider, assignment: Assignment) -> None:
        self._packages[package.id] = package
        self._riders[rider.id] = rider
        self._assignments[assignment.id] = assignment

    async def get_package(self, package_id: str) -> Package | None:
        return self._packages.get(package_id)

    async def list_packages(self, status: PackageStatus | None = None) -> list[Package]:
        items = (p for p in self._packages.values() if status is None or p.status == status)
        return sorted(items, key=lambda p: p.created_at)

    async def delete_package(self, package_id: str) -> Package:
        async with self._lock:
            package = self._packages.get(package_id)
            if package is None:
                raise NotFoundError(f"Package {package_id} not found")
            if package.status != PackageStatus.WAITING:
                raise ConflictError(f"Package {package_id} is already assigned")
            return self._packages.pop(package_id)

    async def get_rider(self, rider_id: str) -> Rider | None:
        return self._riders.get(rider_id)

    async def list_riders(self, status: RiderStatus | None = None) -> list[Rider]:
        items = (r for r in self._riders.values() if status is None or r.status == status)
        return sorted(items, key=lambda r: r.created_at)

    async def delete_rider(self, rider_id: str) -> Rider:
        async with self._lock:
            rider = self._riders.get(rider_id)
            if rider is None:
                raise NotFoundError(f"Rider {rider_id} not found")
            if rider.status != RiderStatus.AVAILABLE:
                raise ConflictError(f"Rider {rider_id} is already assigned")
            return self._riders.pop(rider_id)

    async def list_assignments(self, limit: int = 50) -> list[Assignment]:
        newest_first = sorted(self._assignments.values(), key=lambda a: a.created_at, reverse=True)
        return newest_first[:limit]

    async def reset(self) -> None:
        async with self._lock:
            self._packages.clear()
            self._riders.clear()
            self._assignments.clear()

    async def close(self) -> None:
        return None
