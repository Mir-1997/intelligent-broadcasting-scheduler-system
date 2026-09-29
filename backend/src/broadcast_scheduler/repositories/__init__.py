"""Storage backends and a factory that picks one from settings."""

from broadcast_scheduler.config import Settings
from broadcast_scheduler.repositories.base import SchedulerRepository
from broadcast_scheduler.repositories.memory import InMemorySchedulerRepository


def build_repository(settings: Settings) -> SchedulerRepository:
    """Instantiate the repository selected by ``STORAGE_BACKEND``."""
    if settings.storage_backend == "memory":
        return InMemorySchedulerRepository()

    from broadcast_scheduler.repositories.firestore import (
        FirestoreSchedulerRepository,
        create_firestore_client,
    )

    return FirestoreSchedulerRepository(
        create_firestore_client(settings), collection_prefix=settings.collection_prefix
    )


__all__ = ["InMemorySchedulerRepository", "SchedulerRepository", "build_repository"]
