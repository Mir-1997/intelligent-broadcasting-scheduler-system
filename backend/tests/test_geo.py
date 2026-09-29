import random

import pytest

from broadcast_scheduler.geo import find_nearest, haversine_miles, random_point_within
from broadcast_scheduler.models import Location

TIMES_SQUARE = Location(lat=40.7580, lng=-73.9855)
EMPIRE_STATE = Location(lat=40.7484, lng=-73.9857)


def test_haversine_zero_for_same_point():
    assert haversine_miles(TIMES_SQUARE, TIMES_SQUARE) == 0


def test_haversine_known_distance():
    # Times Square -> Empire State Building is ~0.66 miles.
    assert haversine_miles(TIMES_SQUARE, EMPIRE_STATE) == pytest.approx(0.66, abs=0.02)


def test_haversine_long_distance():
    london = Location(lat=51.5074, lng=-0.1278)
    # NYC -> London is ~3,460 miles.
    assert haversine_miles(TIMES_SQUARE, london) == pytest.approx(3460, rel=0.01)


def test_haversine_is_symmetric():
    assert haversine_miles(TIMES_SQUARE, EMPIRE_STATE) == haversine_miles(
        EMPIRE_STATE, TIMES_SQUARE
    )


def test_find_nearest_picks_closest_within_radius():
    near = Location(lat=40.7600, lng=-73.9855)
    far = Location(lat=40.8000, lng=-73.9855)
    result = find_nearest(TIMES_SQUARE, [far, near], lambda p: p, max_miles=5)
    assert result is not None
    assert result[0] is near


def test_find_nearest_ignores_candidates_outside_radius():
    far = Location(lat=41.0, lng=-73.9855)  # ~17 miles north
    assert find_nearest(TIMES_SQUARE, [far], lambda p: p, max_miles=5) is None


def test_find_nearest_includes_boundary():
    target = Location(lat=40.7580 + 5 / 69.0, lng=-73.9855)
    exact = haversine_miles(TIMES_SQUARE, target)
    assert find_nearest(TIMES_SQUARE, [target], lambda p: p, max_miles=exact) is not None


def test_find_nearest_tie_goes_to_first_candidate():
    a = Location(lat=40.7600, lng=-73.9855)
    b = Location(lat=40.7600, lng=-73.9855)
    result = find_nearest(TIMES_SQUARE, [a, b], lambda p: p, max_miles=5)
    assert result is not None
    assert result[0] is a


def test_find_nearest_empty():
    assert find_nearest(TIMES_SQUARE, [], lambda p: p, max_miles=5) is None


@pytest.mark.parametrize("radius", [0.5, 5, 20])
def test_random_point_within_stays_inside_radius(radius):
    rng = random.Random(42)
    for _ in range(500):
        point = random_point_within(TIMES_SQUARE, radius, rng)
        assert haversine_miles(TIMES_SQUARE, point) <= radius * 1.01


def test_random_point_is_deterministic_with_seed():
    a = random_point_within(TIMES_SQUARE, 5, random.Random(7))
    b = random_point_within(TIMES_SQUARE, 5, random.Random(7))
    assert a == b
