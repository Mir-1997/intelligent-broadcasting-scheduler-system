"""The background task that re-runs matching as waiting packages' radii grow."""

import asyncio
import contextlib

from broadcast_scheduler.config import Settings
from broadcast_scheduler.models import (
    EventType,
    Location,
    MatchTrigger,
    PackageCreate,
    Place,
    RadiusPolicy,
    RiderCreate,
)
from broadcast_scheduler.realtime import EventHub
from broadcast_scheduler.repositories import InMemorySchedulerRepository
from broadcast_scheduler.service import SchedulerService
from tests.conftest import ADMIN_LAT, ADMIN_LNG
from tests.factories import ONE_MILE_LAT


def _service(**policy: float) -> tuple[SchedulerService, EventHub]:
    hub = EventHub()
    settings = Settings(
        storage_backend="memory",
        initial_radius_miles=policy.get("initial", 1),
        radius_increment_miles=policy.get("increment", 2),
        radius_interval_seconds=policy.get("interval", 1),
        max_match_radius_miles=policy.get("max", 5),
    )
    return SchedulerService(InMemorySchedulerRepository(), hub, settings), hub


def _package() -> PackageCreate:
    pickup = Place(lat=ADMIN_LAT, lng=ADMIN_LNG)
    return PackageCreate(pickup=pickup, dropoff=pickup)


def _rider(miles_north: float) -> RiderCreate:
    return RiderCreate(
        name="Ali", location=Location(lat=ADMIN_LAT + ONE_MILE_LAT * miles_north, lng=ADMIN_LNG)
    )


@contextlib.asynccontextmanager
async def _running(service: SchedulerService):
    task = asyncio.create_task(service.run_radius_expander())
    try:
        yield
    finally:
        task.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await task


async def test_package_pairs_once_its_radius_grows_to_reach_a_rider():
    service, _ = _service()
    async with _running(service):
        await service.add_rider(_rider(2.5))  # out of the 1 mi starting radius
        added = await service.add_package(_package())
        assert added.assignment is None

        for _ in range(40):  # radius hits 3 mi after 1 s
            if await service.list_assignments():
                break
            await asyncio.sleep(0.05)

    [assignment] = await service.list_assignments()
    assert assignment.package_id == added.package.id
    assert assignment.trigger == MatchTrigger.RADIUS_EXPANDED


async def test_expander_idles_without_waiting_packages():
    service, _ = _service()
    assert await service._next_expansion_at() is None


async def test_capped_radius_stops_expanding():
    service, _ = _service(initial=1, increment=2, max=1)
    await service.add_package(_package())
    assert await service._next_expansion_at() is None


async def test_policy_update_is_published_and_applied():
    service, hub = _service()
    subscription = hub.subscribe()
    policy = RadiusPolicy(
        initial_radius_miles=3, increment_miles=1, interval_seconds=10, max_radius_miles=4
    )

    assert await service.update_radius_policy(policy) == policy

    assert await service.get_radius_policy() == policy
    event = await subscription.next_message()
    assert EventType.RADIUS_POLICY_UPDATED.value in event
