"""Application service: the single entry point for every scheduler operation.

It persists through the repository and then publishes the matching event(s) to the hub.
Because *all* writes go through here, every change reaches connected clients.
"""

import asyncio
import contextlib
import logging
import random
from datetime import datetime, timedelta

from broadcast_scheduler.config import Settings
from broadcast_scheduler.exceptions import NotFoundError
from broadcast_scheduler.geo import random_point_within
from broadcast_scheduler.matching import new_id
from broadcast_scheduler.models import (
    Admin,
    Assignment,
    EventType,
    Location,
    Package,
    PackageAddResult,
    PackageCreate,
    PackageStatus,
    Place,
    RadiusPolicy,
    Rider,
    RiderAddResult,
    RiderCreate,
    RiderStatus,
    SchedulerEvent,
    SchedulerState,
    SimulationRequest,
    SimulationResult,
    utc_now,
)
from broadcast_scheduler.realtime import EventHub
from broadcast_scheduler.repositories import SchedulerRepository

logger = logging.getLogger(__name__)

_SIMULATED_NAMES = [
    "Ali", "Sara", "Omar", "Ayesha", "Bilal", "Hina", "Usman", "Zara", "Hamza", "Noor",
    "Ahmed", "Fatima", "Danish", "Mahnoor", "Saad", "Iqra", "Faisal", "Amna", "Kamran", "Rabia",
]  # fmt: skip

# Wake just *after* a radius boundary, so the package's grown radius is already in effect.
_EXPANSION_SLACK = timedelta(milliseconds=50)
_RETRY_AFTER = timedelta(seconds=5)


class SchedulerService:
    def __init__(
        self,
        repository: SchedulerRepository,
        hub: EventHub,
        settings: Settings,
        rng: random.Random | None = None,
    ) -> None:
        self._repo = repository
        self._hub = hub
        self._settings = settings
        self._rng = rng or random.Random()
        self._radius_policy: RadiusPolicy | None = None
        # Set whenever the next radius expansion may have moved (new package, policy change).
        self._expansion_changed = asyncio.Event()

    # --- admin ---------------------------------------------------------------------------

    async def ensure_admin(self) -> Admin:
        """Seed the admin document from settings on first start-up."""
        admin = await self._repo.get_admin()
        if admin is None:
            admin = Admin(
                name=self._settings.admin_name,
                location=Location(lat=self._settings.admin_lat, lng=self._settings.admin_lng),
            )
            await self._repo.save_admin(admin)
            logger.info("Seeded admin %s at %s", admin.name, admin.location)
        return admin

    async def get_admin(self) -> Admin:
        return await self.ensure_admin()

    async def update_admin(self, admin: Admin) -> Admin:
        saved = await self._repo.save_admin(admin)
        self._publish(EventType.ADMIN_UPDATED, {"admin": saved.model_dump(mode="json")})
        return saved

    # --- radius policy -------------------------------------------------------------------

    async def get_radius_policy(self) -> RadiusPolicy:
        """The current policy, seeded from settings on first start-up and then cached
        (a single API worker owns it; see realtime.py)."""
        if self._radius_policy is None:
            policy = await self._repo.get_radius_policy()
            if policy is None:
                policy = await self._repo.save_radius_policy(
                    RadiusPolicy(
                        initial_radius_miles=self._settings.initial_radius_miles,
                        increment_miles=self._settings.radius_increment_miles,
                        interval_seconds=self._settings.radius_interval_seconds,
                        max_radius_miles=self._settings.max_match_radius_miles,
                    )
                )
                logger.info("Seeded radius policy %s", policy)
            self._radius_policy = policy
        return self._radius_policy

    async def update_radius_policy(self, policy: RadiusPolicy) -> RadiusPolicy:
        """Apply a new policy to every waiting package, pairing any that now reach a rider."""
        self._radius_policy = await self._repo.save_radius_policy(policy)
        self._publish(
            EventType.RADIUS_POLICY_UPDATED, {"radius_policy": policy.model_dump(mode="json")}
        )
        self._expansion_changed.set()
        await self.expand_matches()
        return policy

    async def expand_matches(self) -> list[Assignment]:
        """Pair waiting packages whose current radius now reaches an available rider."""
        assignments = await self._repo.match_waiting(await self.get_radius_policy())
        for assignment in assignments:
            self._publish_assignment(assignment)
        return assignments

    async def run_radius_expander(self) -> None:
        """Background task: re-run matching each time a waiting package's radius grows.

        Sleeps until the earliest upcoming expansion, or until something changes that
        could move it. Runs until cancelled.
        """
        due: datetime | None = None
        while True:
            self._expansion_changed.clear()
            try:
                if due is not None and utc_now() >= due:
                    await self.expand_matches()
                due = await self._next_expansion_at()
            except Exception:
                logger.exception("Radius expansion failed; retrying")
                due = utc_now() + _RETRY_AFTER
            timeout = None if due is None else max(0.0, (due - utc_now()).total_seconds())
            with contextlib.suppress(TimeoutError):
                await asyncio.wait_for(self._expansion_changed.wait(), timeout)

    async def _next_expansion_at(self) -> datetime | None:
        policy = await self.get_radius_policy()
        now = utc_now()
        upcoming = [
            at
            for p in await self._repo.list_packages(PackageStatus.WAITING)
            if (at := policy.next_expansion_at(p.created_at, now)) is not None
        ]
        return min(upcoming) + _EXPANSION_SLACK if upcoming else None

    # --- packages ------------------------------------------------------------------------

    async def add_package(self, request: PackageCreate) -> PackageAddResult:
        package = Package(
            id=new_id("pkg"), pickup=request.pickup, dropoff=request.dropoff, created_at=utc_now()
        )
        policy = await self.get_radius_policy()
        stored, assignment = await self._repo.add_package(package, policy.initial_radius_miles)
        self._publish(EventType.PACKAGE_ADDED, {"package": stored.model_dump(mode="json")})
        self._publish_assignment(assignment)
        if assignment is None:
            self._expansion_changed.set()
        return PackageAddResult(package=stored, assignment=assignment)

    async def get_package(self, package_id: str) -> Package:
        package = await self._repo.get_package(package_id)
        if package is None:
            raise NotFoundError(f"Package {package_id} not found")
        return package

    async def list_packages(self, status: PackageStatus | None = None) -> list[Package]:
        return await self._repo.list_packages(status)

    async def remove_package(self, package_id: str) -> Package:
        package = await self._repo.delete_package(package_id)
        self._publish(EventType.PACKAGE_REMOVED, {"package_id": package_id})
        return package

    # --- riders --------------------------------------------------------------------------

    async def add_rider(self, request: RiderCreate) -> RiderAddResult:
        rider = Rider(
            id=new_id("rdr"), name=request.name, location=request.location, created_at=utc_now()
        )
        stored, assignment = await self._repo.add_rider(rider, await self.get_radius_policy())
        self._publish(EventType.RIDER_ADDED, {"rider": stored.model_dump(mode="json")})
        self._publish_assignment(assignment)
        return RiderAddResult(rider=stored, assignment=assignment)

    async def get_rider(self, rider_id: str) -> Rider:
        rider = await self._repo.get_rider(rider_id)
        if rider is None:
            raise NotFoundError(f"Rider {rider_id} not found")
        return rider

    async def list_riders(self, status: RiderStatus | None = None) -> list[Rider]:
        return await self._repo.list_riders(status)

    async def remove_rider(self, rider_id: str) -> Rider:
        rider = await self._repo.delete_rider(rider_id)
        self._publish(EventType.RIDER_REMOVED, {"rider_id": rider_id})
        return rider

    # --- scheduler -----------------------------------------------------------------------

    async def list_assignments(self, limit: int = 50) -> list[Assignment]:
        return await self._repo.list_assignments(limit)

    async def get_state(self) -> SchedulerState:
        """What is *in* the scheduler right now: waiting packages and available riders."""
        return SchedulerState(
            admin=await self.ensure_admin(),
            packages=await self._repo.list_packages(PackageStatus.WAITING),
            riders=await self._repo.list_riders(RiderStatus.AVAILABLE),
            radius_policy=await self.get_radius_policy(),
        )

    async def snapshot_event(self) -> SchedulerEvent:
        state = await self.get_state()
        return SchedulerEvent(type=EventType.SNAPSHOT, data=state.model_dump(mode="json"))

    async def simulate(self, request: SimulationRequest) -> SimulationResult:
        """Spawn random riders/packages around the admin, in random interleaved order,
        each going through the normal matching path."""
        admin = await self.ensure_admin()
        kinds = ["package"] * request.packages + ["rider"] * request.riders
        self._rng.shuffle(kinds)

        result = SimulationResult(packages=[], riders=[], assignments=[])
        for kind in kinds:
            if kind == "package":
                pickup = self._random_place(admin.location, request.radius_miles)
                dropoff = self._random_place(pickup, 3.0)
                package_added = await self.add_package(
                    PackageCreate(pickup=pickup, dropoff=dropoff)
                )
                result.packages.append(package_added.package)
                assignment = package_added.assignment
            else:
                rider_added = await self.add_rider(
                    RiderCreate(
                        name=self._rng.choice(_SIMULATED_NAMES),
                        location=random_point_within(
                            admin.location, request.radius_miles, self._rng
                        ),
                    )
                )
                result.riders.append(rider_added.rider)
                assignment = rider_added.assignment
            if assignment is not None:
                result.assignments.append(assignment)
        return result

    async def reset(self) -> None:
        await self._repo.reset()
        self._publish(EventType.SCHEDULER_RESET, {})
        self._expansion_changed.set()

    # --- helpers -------------------------------------------------------------------------

    def _random_place(self, center: Location, radius_miles: float) -> Place:
        point = random_point_within(center, radius_miles, self._rng)
        return Place(lat=point.lat, lng=point.lng)

    def _publish(self, event_type: EventType, data: dict) -> None:
        self._hub.publish(SchedulerEvent(type=event_type, data=data))

    def _publish_assignment(self, assignment: Assignment | None) -> None:
        if assignment is None:
            return
        logger.info(
            "Assigned %s -> %s (%.2f mi)",
            assignment.package_id,
            assignment.rider_id,
            assignment.distance_miles,
        )
        self._publish(
            EventType.ASSIGNMENT_CREATED, {"assignment": assignment.model_dump(mode="json")}
        )
