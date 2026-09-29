"""One behavioural contract, run against every repository implementation."""

import asyncio

import pytest

from broadcast_scheduler.exceptions import ConflictError, NotFoundError
from broadcast_scheduler.models import (
    Admin,
    Location,
    MatchTrigger,
    PackageStatus,
    RadiusPolicy,
    RiderStatus,
)
from tests.factories import ONE_MILE_LAT, make_package, make_rider

LAT, LNG = 40.7580, -73.9855
RADIUS = 5.0
# Fixed 5-mile reach: these tests are about pairing, not growth.
POLICY = RadiusPolicy(initial_radius_miles=RADIUS, increment_miles=0, max_radius_miles=RADIUS)


async def test_admin_round_trip(repository):
    assert await repository.get_admin() is None
    admin = Admin(name="HQ", location=Location(lat=LAT, lng=LNG))
    await repository.save_admin(admin)
    assert await repository.get_admin() == admin


async def test_package_waits_when_no_riders(repository):
    package, assignment = await repository.add_package(make_package(LAT, LNG), RADIUS)
    assert assignment is None
    assert package.status == PackageStatus.WAITING
    assert [p.id for p in await repository.list_packages(PackageStatus.WAITING)] == [package.id]


async def test_package_pairs_with_nearest_rider(repository):
    far, _ = await repository.add_rider(make_rider(LAT + ONE_MILE_LAT * 3, LNG, "far"), POLICY)
    near, _ = await repository.add_rider(make_rider(LAT + ONE_MILE_LAT * 1, LNG, "near"), POLICY)

    package, assignment = await repository.add_package(make_package(LAT, LNG), RADIUS)

    assert assignment is not None
    assert assignment.rider_id == near.id
    assert assignment.trigger == MatchTrigger.PACKAGE_ADDED
    assert assignment.distance_miles == pytest.approx(1.0, abs=0.01)
    assert package.status == PackageStatus.ASSIGNED
    assert package.assigned_rider_id == near.id

    stored_rider = await repository.get_rider(near.id)
    assert stored_rider.status == RiderStatus.ASSIGNED
    assert stored_rider.assigned_package_id == package.id
    # The far rider stays in the scheduler.
    available = await repository.list_riders(RiderStatus.AVAILABLE)
    assert [r.id for r in available] == [far.id]
    assert await repository.list_packages(PackageStatus.WAITING) == []


async def test_package_waits_when_riders_out_of_range(repository):
    await repository.add_rider(make_rider(LAT + ONE_MILE_LAT * 6, LNG), POLICY)
    package, assignment = await repository.add_package(make_package(LAT, LNG), RADIUS)
    assert assignment is None
    assert package.status == PackageStatus.WAITING


async def test_rider_pairs_with_nearest_waiting_package(repository):
    far, _ = await repository.add_package(make_package(LAT + ONE_MILE_LAT * 4, LNG), RADIUS)
    near, _ = await repository.add_package(make_package(LAT + ONE_MILE_LAT * 2, LNG), RADIUS)

    rider, assignment = await repository.add_rider(make_rider(LAT, LNG), POLICY)

    assert assignment is not None
    assert assignment.package_id == near.id
    assert assignment.trigger == MatchTrigger.RIDER_ADDED
    assert rider.status == RiderStatus.ASSIGNED
    assert (await repository.get_package(near.id)).status == PackageStatus.ASSIGNED
    assert [p.id for p in await repository.list_packages(PackageStatus.WAITING)] == [far.id]


async def test_rider_waits_when_nothing_in_range(repository):
    await repository.add_package(make_package(LAT + ONE_MILE_LAT * 10, LNG), RADIUS)
    rider, assignment = await repository.add_rider(make_rider(LAT, LNG), POLICY)
    assert assignment is None
    assert rider.status == RiderStatus.AVAILABLE


async def test_rider_is_never_double_assigned_under_concurrency(repository):
    rider, _ = await repository.add_rider(make_rider(LAT, LNG), POLICY)

    results = await asyncio.gather(
        *(repository.add_package(make_package(LAT, LNG), RADIUS) for _ in range(5))
    )

    assignments = [a for _, a in results if a is not None]
    assert len(assignments) == 1
    assert assignments[0].rider_id == rider.id
    assert len(await repository.list_packages(PackageStatus.WAITING)) == 4


async def test_package_is_never_double_assigned_under_concurrency(repository):
    package, _ = await repository.add_package(make_package(LAT, LNG), RADIUS)

    results = await asyncio.gather(
        *(repository.add_rider(make_rider(LAT, LNG), POLICY) for _ in range(5))
    )

    assignments = [a for _, a in results if a is not None]
    assert len(assignments) == 1
    assert assignments[0].package_id == package.id
    assert len(await repository.list_riders(RiderStatus.AVAILABLE)) == 4


async def test_list_assignments_newest_first_with_limit(repository):
    for i in range(3):
        await repository.add_rider(make_rider(LAT, LNG, f"r{i}"), POLICY)
        await repository.add_package(make_package(LAT, LNG), RADIUS)

    history = await repository.list_assignments(limit=2)
    assert len(history) == 2
    assert history[0].created_at >= history[1].created_at
    assert len(await repository.list_assignments()) == 3


async def test_delete_waiting_package(repository):
    package, _ = await repository.add_package(make_package(LAT, LNG), RADIUS)
    deleted = await repository.delete_package(package.id)
    assert deleted.id == package.id
    assert await repository.get_package(package.id) is None


async def test_delete_missing_package_raises_not_found(repository):
    with pytest.raises(NotFoundError):
        await repository.delete_package("pkg_missing")


async def test_delete_assigned_package_raises_conflict(repository):
    await repository.add_rider(make_rider(LAT, LNG), POLICY)
    package, _ = await repository.add_package(make_package(LAT, LNG), RADIUS)
    with pytest.raises(ConflictError):
        await repository.delete_package(package.id)


async def test_delete_rider_rules(repository):
    rider, _ = await repository.add_rider(make_rider(LAT, LNG), POLICY)
    await repository.delete_rider(rider.id)
    assert await repository.get_rider(rider.id) is None

    with pytest.raises(NotFoundError):
        await repository.delete_rider(rider.id)

    busy, _ = await repository.add_rider(make_rider(LAT, LNG), POLICY)
    await repository.add_package(make_package(LAT, LNG), RADIUS)
    with pytest.raises(ConflictError):
        await repository.delete_rider(busy.id)


async def test_reset_clears_everything_but_admin(repository):
    admin = Admin(name="HQ", location=Location(lat=LAT, lng=LNG))
    await repository.save_admin(admin)
    await repository.add_rider(make_rider(LAT, LNG), POLICY)
    await repository.add_package(make_package(LAT, LNG), RADIUS)
    await repository.add_package(make_package(LAT, LNG), RADIUS)

    await repository.reset()

    assert await repository.list_packages() == []
    assert await repository.list_riders() == []
    assert await repository.list_assignments() == []
    assert await repository.get_admin() == admin


async def test_rider_only_reaches_packages_whose_radius_grew_that_far(repository):
    policy = RadiusPolicy(
        initial_radius_miles=1, increment_miles=2, interval_seconds=60, max_radius_miles=15
    )
    fresh, _ = await repository.add_package(make_package(LAT + ONE_MILE_LAT * 2, LNG), 1)
    old, _ = await repository.add_package(
        make_package(LAT + ONE_MILE_LAT * 2.5, LNG, waited_seconds=61), 1
    )  # waited one interval: radius 3 mi

    rider, assignment = await repository.add_rider(make_rider(LAT, LNG), policy)

    assert assignment is not None
    assert assignment.package_id == old.id  # the nearer package's 1 mi radius falls short
    assert [p.id for p in await repository.list_packages(PackageStatus.WAITING)] == [fresh.id]


async def test_match_waiting_pairs_packages_whose_radius_now_reaches_a_rider(repository):
    policy = RadiusPolicy(
        initial_radius_miles=1, increment_miles=2, interval_seconds=60, max_radius_miles=15
    )
    rider, _ = await repository.add_rider(make_rider(LAT + ONE_MILE_LAT * 2.5, LNG), policy)
    package, _ = await repository.add_package(
        make_package(LAT, LNG, waited_seconds=61), policy.initial_radius_miles
    )
    assert package.status == PackageStatus.WAITING  # 2.5 mi away, 1 mi reach on arrival

    assignments = await repository.match_waiting(policy)

    assert [(a.package_id, a.rider_id) for a in assignments] == [(package.id, rider.id)]
    assert assignments[0].trigger == MatchTrigger.RADIUS_EXPANDED
    assert (await repository.get_package(package.id)).status == PackageStatus.ASSIGNED
    assert (await repository.get_rider(rider.id)).status == RiderStatus.ASSIGNED
    assert await repository.match_waiting(policy) == []  # idempotent


async def test_match_waiting_serves_oldest_package_first(repository):
    policy = RadiusPolicy(
        initial_radius_miles=1, increment_miles=2, interval_seconds=60, max_radius_miles=15
    )
    rider, _ = await repository.add_rider(make_rider(LAT + ONE_MILE_LAT * 2, LNG), policy)
    newer, _ = await repository.add_package(make_package(LAT, LNG, waited_seconds=61), 1)
    older, _ = await repository.add_package(make_package(LAT, LNG, waited_seconds=120), 1)

    assignments = await repository.match_waiting(policy)

    assert [a.package_id for a in assignments] == [older.id]
    assert [p.id for p in await repository.list_packages(PackageStatus.WAITING)] == [newer.id]


async def test_radius_policy_round_trip_survives_reset(repository):
    assert await repository.get_radius_policy() is None
    policy = RadiusPolicy(initial_radius_miles=2, increment_miles=1, interval_seconds=10)
    await repository.save_radius_policy(policy)
    await repository.reset()
    assert await repository.get_radius_policy() == policy
