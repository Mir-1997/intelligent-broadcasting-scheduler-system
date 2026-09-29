"""Shared fixtures.

Repository-level tests run against the in-memory store always, and against the Firestore
emulator too when ``FIRESTORE_EMULATOR_HOST`` is set (e.g. via ``firebase emulators:exec``).
"""

import os
import uuid
from collections.abc import AsyncIterator, Iterator

import pytest
from fastapi.testclient import TestClient

from broadcast_scheduler.config import Settings
from broadcast_scheduler.main import create_app
from broadcast_scheduler.repositories import InMemorySchedulerRepository, SchedulerRepository

ADMIN_LAT, ADMIN_LNG = 40.7580, -73.9855

# Never let a developer's backend/.env (e.g. pointing at a real project) leak into tests.
Settings.model_config["env_file"] = None


@pytest.fixture
def settings() -> Settings:
    return Settings(
        storage_backend="memory",
        admin_name="Test Admin",
        admin_lat=ADMIN_LAT,
        admin_lng=ADMIN_LNG,
        max_match_radius_miles=5.0,
    )


@pytest.fixture
def client(settings: Settings) -> Iterator[TestClient]:
    """API client backed by a fresh in-memory repository."""
    app = create_app(settings=settings, repository=InMemorySchedulerRepository())
    with TestClient(app) as test_client:
        yield test_client


def _firestore_available() -> bool:
    return bool(os.environ.get("FIRESTORE_EMULATOR_HOST"))


@pytest.fixture(
    params=[
        "memory",
        pytest.param(
            "firestore",
            marks=[
                pytest.mark.firestore,
                pytest.mark.skipif(
                    not _firestore_available(), reason="FIRESTORE_EMULATOR_HOST not set"
                ),
            ],
        ),
    ]
)
async def repository(request: pytest.FixtureRequest) -> AsyncIterator[SchedulerRepository]:
    """Every repository implementation, so one test suite enforces one contract."""
    if request.param == "memory":
        yield InMemorySchedulerRepository()
        return

    from broadcast_scheduler.repositories.firestore import (
        FirestoreSchedulerRepository,
        create_firestore_client,
    )

    settings = Settings(firestore_emulator_host=os.environ["FIRESTORE_EMULATOR_HOST"])
    repo = FirestoreSchedulerRepository(
        create_firestore_client(settings), collection_prefix=f"test_{uuid.uuid4().hex[:8]}_"
    )
    try:
        yield repo
    finally:
        await repo.reset()
        await repo.close()
