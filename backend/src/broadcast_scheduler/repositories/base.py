"""The storage contract every backend must satisfy."""

from typing import Protocol

from broadcast_scheduler.models import (
    Admin,
    Assignment,
    Package,
    PackageStatus,
    Rider,
    RiderStatus,
)


class SchedulerRepository(Protocol):
    """Persistence for admin, packages, riders and assignments.

    ``add_package`` and ``add_rider`` are the heart of the system: each one stores the new
    item *and* pairs it with its nearest counterpart atomically, so that two concurrent
    arrivals can never both claim the same rider or package.
    """

    async def get_admin(self) -> Admin | None: ...

    async def save_admin(self, admin: Admin) -> Admin: ...

    async def add_package(
        self, package: Package, max_radius_miles: float
    ) -> tuple[Package, Assignment | None]:
        """Store a new waiting package, pairing it with the nearest available rider.

        Returns the stored package (``assigned`` if paired) and the assignment, if any.
        """
        ...

    async def add_rider(
        self, rider: Rider, max_radius_miles: float
    ) -> tuple[Rider, Assignment | None]:
        """Store a new available rider, pairing it with the nearest waiting package."""
        ...

    async def get_package(self, package_id: str) -> Package | None: ...

    async def list_packages(self, status: PackageStatus | None = None) -> list[Package]:
        """Packages, oldest first, optionally filtered by status."""
        ...

    async def delete_package(self, package_id: str) -> Package:
        """Remove a *waiting* package. Raises NotFoundError / ConflictError."""
        ...

    async def get_rider(self, rider_id: str) -> Rider | None: ...

    async def list_riders(self, status: RiderStatus | None = None) -> list[Rider]:
        """Riders, oldest first, optionally filtered by status."""
        ...

    async def delete_rider(self, rider_id: str) -> Rider:
        """Remove an *available* rider. Raises NotFoundError / ConflictError."""
        ...

    async def list_assignments(self, limit: int = 50) -> list[Assignment]:
        """Assignments, newest first."""
        ...

    async def reset(self) -> None:
        """Delete all packages, riders and assignments (the admin is kept)."""
        ...

    async def close(self) -> None: ...
