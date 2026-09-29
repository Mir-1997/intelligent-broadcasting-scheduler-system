"""Tiny builders for domain objects used across tests."""

from datetime import timedelta

from broadcast_scheduler.matching import new_id
from broadcast_scheduler.models import Location, Package, Place, Rider, utc_now

# ~1 mile of latitude, for placing things at known distances.
ONE_MILE_LAT = 1 / 69.0

_clock = utc_now()


def _tick():
    """Strictly increasing timestamps, so 'oldest first' ordering is deterministic."""
    global _clock
    _clock = _clock + timedelta(milliseconds=1)
    return _clock


def make_rider(lat: float, lng: float, name: str = "Rider") -> Rider:
    return Rider(
        id=new_id("rdr"), name=name, location=Location(lat=lat, lng=lng), created_at=_tick()
    )


def make_package(lat: float, lng: float) -> Package:
    return Package(
        id=new_id("pkg"),
        pickup=Place(lat=lat, lng=lng, address="pickup"),
        dropoff=Place(lat=lat + 0.01, lng=lng, address="dropoff"),
        created_at=_tick(),
    )
