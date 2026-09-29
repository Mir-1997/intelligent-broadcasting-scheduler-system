"""Pure geographic helpers. No I/O, so they are trivially unit-testable."""

import math
import random
from collections.abc import Callable, Iterable

from broadcast_scheduler.models import Location

EARTH_RADIUS_MILES = 3958.7613
MILES_PER_DEGREE_LAT = 69.0


def haversine_miles(a: Location, b: Location) -> float:
    """Great-circle distance between two coordinates, in miles."""
    lat1, lat2 = math.radians(a.lat), math.radians(b.lat)
    d_lat = lat2 - lat1
    d_lng = math.radians(b.lng - a.lng)
    h = math.sin(d_lat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(d_lng / 2) ** 2
    return 2 * EARTH_RADIUS_MILES * math.asin(min(1.0, math.sqrt(h)))


def find_nearest[T](
    origin: Location,
    candidates: Iterable[T],
    location_of: Callable[[T], Location],
    max_miles: float | Callable[[T], float],
) -> tuple[T, float] | None:
    """Return the candidate closest to ``origin`` and its distance, or ``None``.

    Candidates further than ``max_miles`` are ignored; pass a function instead of a
    number when each candidate has its own reach. On an exact distance tie the
    candidate that appears first wins, so callers pass candidates oldest-first to get
    first-come-first-served fairness.
    """
    reach_of = max_miles if callable(max_miles) else lambda _: max_miles
    best: tuple[T, float] | None = None
    for candidate in candidates:
        distance = haversine_miles(origin, location_of(candidate))
        if distance <= reach_of(candidate) and (best is None or distance < best[1]):
            best = (candidate, distance)
    return best


def random_point_within(
    center: Location, radius_miles: float, rng: random.Random | None = None
) -> Location:
    """A uniformly distributed random point inside a circle around ``center``.

    Uses a flat-earth approximation, which is accurate to well under 1% at the
    city-scale radii the simulator uses.
    """
    rng = rng or random.Random()
    distance = radius_miles * math.sqrt(rng.random())  # sqrt => uniform over the area
    bearing = rng.uniform(0, 2 * math.pi)
    d_lat = distance * math.cos(bearing) / MILES_PER_DEGREE_LAT
    miles_per_degree_lng = MILES_PER_DEGREE_LAT * max(math.cos(math.radians(center.lat)), 1e-6)
    d_lng = distance * math.sin(bearing) / miles_per_degree_lng
    return Location(
        lat=max(-90.0, min(90.0, center.lat + d_lat)),
        lng=((center.lng + d_lng + 180) % 360) - 180,
    )
