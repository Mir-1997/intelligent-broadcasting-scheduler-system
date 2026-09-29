"""Domain and API schemas.

The same Pydantic models are used for request validation, response serialisation,
Firestore documents and WebSocket event payloads, so there is exactly one definition
of every shape in the system.
"""

from datetime import UTC, datetime
from enum import StrEnum
from typing import Any

from pydantic import BaseModel, Field


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


class EventType(StrEnum):
    """Every message type sent over ``/ws/scheduler``."""

    SNAPSHOT = "scheduler.snapshot"
    PACKAGE_ADDED = "package.added"
    PACKAGE_REMOVED = "package.removed"
    RIDER_ADDED = "rider.added"
    RIDER_REMOVED = "rider.removed"
    ASSIGNMENT_CREATED = "assignment.created"
    ADMIN_UPDATED = "admin.updated"
    SCHEDULER_RESET = "scheduler.reset"


# --------------------------------------------------------------------------------------
# Entities
# --------------------------------------------------------------------------------------


class Admin(BaseModel):
    """The dispatcher. Their location is the centre of the map."""

    name: str = Field(min_length=1, max_length=60)
    location: Location


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
    max_match_radius_miles: float


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
