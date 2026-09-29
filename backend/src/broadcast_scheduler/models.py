"""Domain and API schemas.

The same Pydantic models are used for request validation, response serialisation,
Firestore documents and WebSocket event payloads, so there is exactly one definition
of every shape in the system.
"""

import math
from datetime import UTC, datetime, timedelta
from enum import StrEnum
from typing import Any, Self

from pydantic import BaseModel, Field, model_validator


def utc_now() -> datetime:
    """Timezone-aware 'now' in UTC. All timestamps in the system use this."""
    return datetime.now(UTC)


# --------------------------------------------------------------------------------------
# Value objects
# --------------------------------------------------------------------------------------


class Location(BaseModel):
    """A WGS84 coordinate."""

    lat: float = Field(ge=-90, le=90, examples=[40.7580])
    lng: float = Field(ge=-180, le=180, examples=[-73.9855])


class Place(Location):
    """A coordinate with an optional human-readable address."""

    address: str = Field(default="", max_length=200, examples=["1560 Broadway, New York"])


# --------------------------------------------------------------------------------------
# Enums
# --------------------------------------------------------------------------------------


class PackageStatus(StrEnum):
    WAITING = "waiting"
    """In the scheduler, waiting for a rider within range."""
    ASSIGNED = "assigned"
    """Paired with a rider; no longer part of the scheduler."""


class RiderStatus(StrEnum):
    AVAILABLE = "available"
    """In the scheduler, waiting for a package within range."""
    ASSIGNED = "assigned"
    """Paired with a package; no longer part of the scheduler."""


class MatchTrigger(StrEnum):
    """Which arrival caused a pairing."""

    PACKAGE_ADDED = "package_added"
    RIDER_ADDED = "rider_added"
    RADIUS_EXPANDED = "radius_expanded"
    """A waiting package's search radius grew (or the policy changed) to reach a rider."""


class EventType(StrEnum):
    """Every message type sent over ``/ws/scheduler``."""

    SNAPSHOT = "scheduler.snapshot"
    PACKAGE_ADDED = "package.added"
    PACKAGE_REMOVED = "package.removed"
    RIDER_ADDED = "rider.added"
    RIDER_REMOVED = "rider.removed"
    ASSIGNMENT_CREATED = "assignment.created"
    ADMIN_UPDATED = "admin.updated"
    RADIUS_POLICY_UPDATED = "radius_policy.updated"
    SCHEDULER_RESET = "scheduler.reset"


# --------------------------------------------------------------------------------------
# Entities
# --------------------------------------------------------------------------------------


class Admin(BaseModel):
    """The dispatcher. Their location is the centre of the map."""

    name: str = Field(min_length=1, max_length=60)
    location: Location


class RadiusPolicy(BaseModel):
    """How far a waiting package searches for a rider, growing the longer it waits.

    A package starts at ``initial_radius_miles``; every ``interval_seconds`` it has been
    waiting, its radius grows by ``increment_miles``, up to ``max_radius_miles``. The
    radius is derived from the package's age, so changing the policy applies to every
    waiting package immediately.
    """

    initial_radius_miles: float = Field(default=1.0, gt=0, le=100, examples=[1.0])
    increment_miles: float = Field(default=2.0, ge=0, le=100, examples=[2.0])
    interval_seconds: float = Field(default=30.0, ge=1, le=86_400, examples=[30.0])
    max_radius_miles: float = Field(default=15.0, gt=0, le=200, examples=[15.0])

    @model_validator(mode="after")
    def _max_covers_initial(self) -> Self:
        if self.max_radius_miles < self.initial_radius_miles:
            raise ValueError("max_radius_miles must be at least initial_radius_miles")
        return self

    def _steps(self, created_at: datetime, now: datetime) -> int:
        """Completed intervals since ``created_at`` (0 if the clock reads earlier)."""
        waited = max(0.0, (now - created_at).total_seconds())
        return math.floor(waited / self.interval_seconds)

    def radius_at(self, created_at: datetime, now: datetime) -> float:
        """Search radius of a package created at ``created_at``, as of ``now``."""
        grown = self.initial_radius_miles + self.increment_miles * self._steps(created_at, now)
        return min(grown, self.max_radius_miles)

    def next_expansion_at(self, created_at: datetime, now: datetime) -> datetime | None:
        """When that package's radius next grows, or ``None`` once it is capped."""
        if self.increment_miles == 0 or self.radius_at(created_at, now) >= self.max_radius_miles:
            return None
        steps = self._steps(created_at, now) + 1
        return created_at + timedelta(seconds=steps * self.interval_seconds)


class PackageCreate(BaseModel):
    """Request body for ``POST /packages``."""

    pickup: Place
    dropoff: Place


class Package(BaseModel):
    id: str = Field(examples=["pkg_3f9a1c2b"])
    pickup: Place
    dropoff: Place
    status: PackageStatus = PackageStatus.WAITING
    created_at: datetime
    assigned_rider_id: str | None = None
    assigned_at: datetime | None = None


class RiderCreate(BaseModel):
    """Request body for ``POST /riders``."""

    name: str = Field(min_length=1, max_length=60, examples=["Ali"])
    location: Location


class Rider(BaseModel):
    id: str = Field(examples=["rdr_8b20e4d1"])
    name: str
    location: Location
    status: RiderStatus = RiderStatus.AVAILABLE
    created_at: datetime
    assigned_package_id: str | None = None
    assigned_at: datetime | None = None


class Assignment(BaseModel):
    """A package/rider pairing. Denormalised so the history panel needs no joins."""

    id: str = Field(examples=["asg_51c7d0aa"])
    package_id: str
    rider_id: str
    rider_name: str
    distance_miles: float = Field(description="Haversine distance from rider to pickup.")
    pickup: Place
    dropoff: Place
    rider_location: Location
    trigger: MatchTrigger
    created_at: datetime


# --------------------------------------------------------------------------------------
# Composite responses
# --------------------------------------------------------------------------------------


class PackageAddResult(BaseModel):
    """Response of ``POST /packages``. ``assignment`` is set if the package was paired."""

    package: Package
    assignment: Assignment | None = None


class RiderAddResult(BaseModel):
    """Response of ``POST /riders``. ``assignment`` is set if the rider was paired."""

    rider: Rider
    assignment: Assignment | None = None


class SchedulerState(BaseModel):
    """Everything currently *in* the scheduler (waiting packages and available riders)."""

    admin: Admin
    packages: list[Package]
    riders: list[Rider]
    radius_policy: RadiusPolicy


class SimulationRequest(BaseModel):
    """Request body for ``POST /simulate``."""

    packages: int = Field(default=5, ge=0, le=50)
    riders: int = Field(default=5, ge=0, le=50)
    radius_miles: float = Field(
        default=8.0,
        gt=0,
        le=50,
        description="Spawn radius around the admin. Larger than the match radius so that "
        "some items stay waiting.",
    )


class SimulationResult(BaseModel):
    packages: list[Package]
    riders: list[Rider]
    assignments: list[Assignment]


class SchedulerEvent(BaseModel):
    """Envelope for every WebSocket message."""

    type: EventType
    data: dict[str, Any]
    timestamp: datetime = Field(default_factory=utc_now)
