# Matching algorithm

Source: `backend/src/broadcast_scheduler/matching.py`, `geo.py`, and the `add_package` /
`add_rider` methods of each repository.

## 1. The rule

> When an item enters the scheduler, it is paired **immediately** with the **nearest
> eligible counterpart** whose distance is **≤ `MAX_MATCH_RADIUS_MILES`** (default 5).
> If none qualifies, the item **waits** in the scheduler.

| Arrival | Candidates | Distance measured between |
|---|---|---|
| New package | riders with `status == "available"` | rider location ↔ package **pickup** |
| New rider | packages with `status == "waiting"` | rider location ↔ package **pickup** |

The drop-off is never used for matching. It's stored and displayed only.

A waiting item never "wakes up" by itself. It pairs only when a *new* counterpart arrives
within range. (A waiting package and a waiting rider more than 5 miles apart both stay
waiting until something else arrives.)

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
| Assignment | new `asg_…` id, both ids, `rider_name`, `distance_miles` (rounded to 0.001), pickup, dropoff, rider location, `trigger` (`package_added` / `rider_added`), `created_at` |

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

Admin at Times Square (40.7580, −73.9855), radius 5 mi.

1. `POST /riders` Ali at (40.7644, −73.9735). No waiting packages, so **Ali waits**.
2. `POST /packages` pickup (40.7580, −73.9855). The only available rider is Ali at
   **0.768 mi** ≤ 5, so **paired**. The response includes `assignment.trigger ==
   "package_added"`, and the sockets receive `package.added` (status `assigned`) and then
   `assignment.created`.
3. `POST /packages` pickup 6 mi north. No available riders, so **waits**. The map shows the
   package with its 5-mile circle.
4. `POST /riders` Sara 1 mi from that pickup, so **paired** with `trigger ==
   "rider_added"`.
