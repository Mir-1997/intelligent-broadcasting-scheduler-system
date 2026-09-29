"""Matching rules, shared by every repository implementation.

Repositories own *atomicity* (reading candidates and writing the pairing in one
transaction); this module owns the *decision*: who pairs with whom and what the
resulting records look like.
"""

import uuid
from datetime import datetime

from broadcast_scheduler.geo import find_nearest
from broadcast_scheduler.models import (
    Assignment,
    MatchTrigger,
    Package,
    PackageStatus,
    Rider,
    RiderStatus,
)


def new_id(prefix: str) -> str:
    """Short, prefixed, random id such as ``pkg_3f9a1c2b``."""
    return f"{prefix}_{uuid.uuid4().hex[:8]}"


def nearest_rider(
    package: Package, riders: list[Rider], max_miles: float
) -> tuple[Rider, float] | None:
    """Closest *available* rider to the package's pickup point, oldest rider on ties."""
    available = sorted(
        (r for r in riders if r.status == RiderStatus.AVAILABLE), key=lambda r: r.created_at
    )
    return find_nearest(package.pickup, available, lambda r: r.location, max_miles)


def nearest_package(
    rider: Rider, packages: list[Package], max_miles: float
) -> tuple[Package, float] | None:
    """Closest *waiting* package pickup to the rider, oldest package on ties."""
    waiting = sorted(
        (p for p in packages if p.status == PackageStatus.WAITING), key=lambda p: p.created_at
    )
    return find_nearest(rider.location, waiting, lambda p: p.pickup, max_miles)


def pair(
    package: Package,
    rider: Rider,
    distance_miles: float,
    trigger: MatchTrigger,
    now: datetime,
) -> tuple[Package, Rider, Assignment]:
    """Produce the updated package, updated rider and the new assignment record."""
    assigned_package = package.model_copy(
        update={
            "status": PackageStatus.ASSIGNED,
            "assigned_rider_id": rider.id,
            "assigned_at": now,
        }
    )
    assigned_rider = rider.model_copy(
        update={
            "status": RiderStatus.ASSIGNED,
            "assigned_package_id": package.id,
            "assigned_at": now,
        }
    )
    assignment = Assignment(
        id=new_id("asg"),
        package_id=package.id,
        rider_id=rider.id,
        rider_name=rider.name,
        distance_miles=round(distance_miles, 3),
        pickup=package.pickup,
        dropoff=package.dropoff,
        rider_location=rider.location,
        trigger=trigger,
        created_at=now,
    )
    return assigned_package, assigned_rider, assignment
