from datetime import timedelta

import pytest
from pydantic import ValidationError

from broadcast_scheduler.matching import (
    match_waiting,
    nearest_package,
    nearest_rider,
    new_id,
    pair,
)
from broadcast_scheduler.models import (
    MatchTrigger,
    PackageStatus,
    RadiusPolicy,
    RiderStatus,
    utc_now,
)
from tests.factories import ONE_MILE_LAT, make_package, make_rider

LAT, LNG = 40.7580, -73.9855
FIVE_MILES = RadiusPolicy(initial_radius_miles=5, increment_miles=0, max_radius_miles=5)
GROWING = RadiusPolicy(
    initial_radius_miles=1, increment_miles=2, interval_seconds=30, max_radius_miles=6
)


def test_new_id_has_prefix_and_is_unique():
    ids = {new_id("pkg") for _ in range(1000)}
    assert len(ids) == 1000
    assert all(i.startswith("pkg_") and len(i) == 12 for i in ids)


def test_nearest_rider_skips_assigned_riders():
    package = make_package(LAT, LNG)
    close_but_busy = make_rider(LAT + ONE_MILE_LAT * 0.1, LNG).model_copy(
        update={"status": RiderStatus.ASSIGNED}
    )
    free = make_rider(LAT + ONE_MILE_LAT * 2, LNG)
    match = nearest_rider(package, [close_but_busy, free], max_miles=5)
    assert match is not None and match[0].id == free.id


def test_nearest_rider_tie_prefers_oldest_rider():
    package = make_package(LAT, LNG)
    older = make_rider(LAT + ONE_MILE_LAT, LNG, "older")
    newer = make_rider(LAT + ONE_MILE_LAT, LNG, "newer")
    match = nearest_rider(package, [newer, older], max_miles=5)
    assert match is not None and match[0].name == "older"


def test_nearest_package_skips_assigned_packages():
    rider = make_rider(LAT, LNG)
    busy = make_package(LAT, LNG).model_copy(update={"status": PackageStatus.ASSIGNED})
    waiting = make_package(LAT + ONE_MILE_LAT, LNG)
    match = nearest_package(rider, [busy, waiting], FIVE_MILES, utc_now())
    assert match is not None and match[0].id == waiting.id


def test_nearest_package_none_out_of_range():
    rider = make_rider(LAT, LNG)
    far = make_package(LAT + ONE_MILE_LAT * 6, LNG)
    assert nearest_package(rider, [far], FIVE_MILES, utc_now()) is None


def test_pair_updates_both_sides_and_builds_assignment():
    package, rider = make_package(LAT, LNG), make_rider(LAT, LNG, "Sara")
    now = utc_now()
    p, r, a = pair(package, rider, 1.23456, MatchTrigger.PACKAGE_ADDED, now)

    assert p.status == PackageStatus.ASSIGNED and p.assigned_rider_id == rider.id
    assert r.status == RiderStatus.ASSIGNED and r.assigned_package_id == package.id
    assert p.assigned_at == r.assigned_at == a.created_at == now
    assert a.package_id == package.id and a.rider_id == rider.id
    assert a.rider_name == "Sara"
    assert a.distance_miles == 1.235
    assert a.trigger == MatchTrigger.PACKAGE_ADDED
    # originals are untouched (models are copied, not mutated)
    assert package.status == PackageStatus.WAITING and rider.status == RiderStatus.AVAILABLE


@pytest.mark.parametrize(
    ("waited", "radius"),
    [(0, 1), (29.9, 1), (30, 3), (59, 3), (60, 5), (90, 6), (3600, 6), (-5, 1)],
)
def test_radius_grows_by_increment_each_interval_up_to_the_cap(waited, radius):
    created = utc_now()
    assert GROWING.radius_at(created, created + timedelta(seconds=waited)) == radius


def test_next_expansion_is_the_next_interval_boundary_until_capped():
    created = utc_now()
    assert GROWING.next_expansion_at(created, created) == created + timedelta(seconds=30)
    assert GROWING.next_expansion_at(
        created, created + timedelta(seconds=45)
    ) == created + timedelta(seconds=60)
    assert GROWING.next_expansion_at(created, created + timedelta(seconds=90)) is None
    assert FIVE_MILES.next_expansion_at(created, created) is None  # no increment


def test_policy_rejects_max_below_initial():
    with pytest.raises(ValidationError):
        RadiusPolicy(initial_radius_miles=5, max_radius_miles=2)


def test_nearest_package_uses_each_packages_own_radius():
    rider = make_rider(LAT, LNG)
    near_but_new = make_package(LAT + ONE_MILE_LAT * 2, LNG)
    farther_but_waited = make_package(LAT + ONE_MILE_LAT * 2.5, LNG, waited_seconds=31)
    match = nearest_package(rider, [near_but_new, farther_but_waited], GROWING, utc_now())
    assert match is not None and match[0].id == farther_but_waited.id


def test_match_waiting_gives_each_rider_to_one_package():
    riders = [make_rider(LAT + ONE_MILE_LAT * 0.5, LNG, "only")]
    packages = [make_package(LAT, LNG), make_package(LAT, LNG)]
    pairs = match_waiting(packages, riders, GROWING, utc_now())
    assert len(pairs) == 1
    package, rider, assignment = pairs[0]
    assert package.id == packages[0].id and rider.name == "only"
    assert assignment.trigger == MatchTrigger.RADIUS_EXPANDED
