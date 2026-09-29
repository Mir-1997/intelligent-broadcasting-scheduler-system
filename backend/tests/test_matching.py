from broadcast_scheduler.matching import nearest_package, nearest_rider, new_id, pair
from broadcast_scheduler.models import MatchTrigger, PackageStatus, RiderStatus, utc_now
from tests.factories import ONE_MILE_LAT, make_package, make_rider

LAT, LNG = 40.7580, -73.9855


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
    match = nearest_package(rider, [busy, waiting], max_miles=5)
    assert match is not None and match[0].id == waiting.id


def test_nearest_package_none_out_of_range():
    rider = make_rider(LAT, LNG)
    far = make_package(LAT + ONE_MILE_LAT * 6, LNG)
    assert nearest_package(rider, [far], max_miles=5) is None


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
