# Matching algorithm

Source: `backend/src/broadcast_scheduler/matching.py`, `geo.py`, and the `add_package` /
`add_rider` methods of each repository.

## 1. The rule

> When an item enters the scheduler, it is paired **immediately** with the **nearest
> eligible counterpart** within the package's current **search radius**. If none
> qualifies, the item **waits** in the scheduler, and a waiting package's search radius
> **grows over time** until it reaches a rider or the cap.

| Arrival | Candidates | Distance measured between |
|---|---|---|
| New package | riders with `status == "available"` | rider location ↔ package **pickup** |
| New rider | packages with `status == "waiting"` | rider location ↔ package **pickup** |

The drop-off is never used for matching. It's stored and displayed only.

### Growing search radius

Each package has its own radius, derived from how long it has waited and the
`RadiusPolicy` (`GET`/`PUT /settings/radius`, editable from the UI):

```
radius = min(initial_radius_miles + increment_miles × ⌊waited / interval_seconds⌋,
             max_radius_miles)
```

Defaults: start at **1 mi**, **+2 mi every 30 s**, capped at **15 mi**. So a package
searches 1 → 3 → 5 → … → 15 mi. Riders have no radius of their own: a new rider pairs with
the nearest waiting package whose *current* radius reaches it.

Because the radius is a pure function of the package's age, nothing is stored per package,
and a policy change applies to every waiting package at once (a smaller policy can shrink
radii too).

**Expansion sweep.** A background task (`SchedulerService.run_radius_expander`) sleeps until
the earliest upcoming radius growth among waiting packages, then runs `match_waiting`:
waiting packages, **oldest first**, each take their nearest still-available rider inside
their new radius, atomically (one transaction / one lock). Pairings made this way have
`trigger == "radius_expanded"`. The task wakes early whenever a package is added, the policy
changes or the scheduler is reset, and it idles when nothing is waiting or every package
is at the cap. A `PUT /settings/radius` also runs the sweep immediately.

## 2. Distance: haversine

```python
def haversine_miles(a, b):
    lat1, lat2 = radians(a.lat), radians(b.lat)
    d_lat = lat2 - lat1
    d_lng = radians(b.lng - a.lng)
    h = sin(d_lat/2)**2 + cos(lat1) * cos(lat2) * sin(d_lng/2)**2
    return 2 * 3958.7613 * asin(min(1, sqrt(h)))    # Earth's mean radius in miles
```

This is great-circle ("as the crow flies") distance. It matches the spec, needs no API key,
and costs nothing. Road distance would be a drop-in change inside `find_nearest`; see
[roadmap.md](roadmap.md).

Reference values from the tests: Times Square → Empire State Building ≈ 0.66 mi; NYC →
London ≈ 3,460 mi.

## 3. Choosing the nearest

`geo.find_nearest(origin, candidates, location_of, max_miles)` does a single linear scan:

- skips candidates farther than `max_miles` (the boundary itself counts: `<=`)
- keeps the strictly smaller distance, so **on an exact tie the first candidate wins**
- callers pass candidates **sorted oldest-first** (`created_at`), which makes ties
  first-come, first-served

`nearest_rider` and `nearest_package` also filter by status as a second line of defence.
Firestore already filters by status in the query.

## 4. Producing the pairing

`matching.pair(package, rider, distance, trigger, now)` returns three new objects (the
inputs are never mutated):

| Object | Changes |
|---|---|
| Package | `status → assigned`, `assigned_rider_id`, `assigned_at` |
| Rider | `status → assigned`, `assigned_package_id`, `assigned_at` |
| Assignment | new `asg_…` id, both ids, `rider_name`, `distance_miles` (rounded to 0.001), pickup, dropoff, rider location, `trigger` (`package_added` / `rider_added` / `radius_expanded`), `created_at` |

The assignment is **denormalised** on purpose: the history panel and the prompt can show
everything without looking anything else up, even after the package or rider is deleted by
a reset.

## 5. Atomicity: why no rider is ever double-assigned

Race to prevent: two packages arrive at the same moment, both see rider R as the nearest
available, and both claim R.

**Firestore** (`repositories/firestore.py`):

```python
@async_transactional
async def run(tx):
    riders = [...  async for s in await tx.get(available_riders_query)]   # transactional read
    match = nearest_rider(package, riders, radius)
    if match is None:
        tx.create(package_ref, package)                  # just wait
        return
    tx.create(package_ref, assigned_package)
    tx.update(rider_ref, {status, assigned_package_id, assigned_at})
    tx.create(assignment_ref, assignment)
```

- The candidate query is read **inside the transaction**. If another transaction commits a
  change to any document we read (R becomes assigned) before we commit, Firestore aborts
  ours and `async_transactional` **re-runs the function** with fresh data. The retry sees R
  as unavailable and picks the next-nearest rider, or waits.
- The existing side is written with `update`, which fails if the document vanished
  meanwhile (e.g. deleted). The newly-arrived side is written with `create`, which fails on
  an id collision instead of overwriting.

**In-memory** (`repositories/memory.py`): one `asyncio.Lock` around the read-decide-write
sequence gives the same guarantee within a single process.

Both are checked by the same tests: 5 concurrent packages against 1 rider must produce
exactly 1 assignment and 4 waiting packages, and the mirror test does the same for riders.

## 6. Scaling the candidate search

Each arrival reads *all* candidates of the opposite kind. That's O(n) documents per
arrival, fine for a demo and for a few hundred live items. To scale:

1. **Geohash prefix queries.** Store a geohash per item and query only the cells covering
   the 5-mile circle, then run haversine on those. This is the standard Firestore approach,
   e.g. with GeoFire-style helpers.
2. **A geo index** (Redis GEO, PostGIS) for proximity, with Firestore as the system of
   record, as the production engine does.

Either change stays inside the repository. `matching.py` and the API don't change.

## 7. Worked example

Admin at Times Square (40.7580, −73.9855); for simplicity this example uses a fixed
5 mi radius (`initial_radius_miles = max_radius_miles = 5`).

1. `POST /riders` Ali at (40.7644, −73.9735). No waiting packages, so **Ali waits**.
2. `POST /packages` pickup (40.7580, −73.9855). The only available rider is Ali at
   **0.768 mi** ≤ 5, so **paired**. The response includes `assignment.trigger ==
   "package_added"`, and the sockets receive `package.added` (status `assigned`) and then
   `assignment.created`.
3. `POST /packages` pickup 6 mi north. No available riders, so **waits**. The map shows the
   package with its 5-mile circle.
4. `POST /riders` Sara 1 mi from that pickup, so **paired** with `trigger ==
   "rider_added"`.
