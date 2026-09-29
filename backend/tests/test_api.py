"""HTTP API behaviour (in-memory storage)."""

from tests.conftest import ADMIN_LAT, ADMIN_LNG
from tests.factories import ONE_MILE_LAT


def rider_body(lat=ADMIN_LAT, lng=ADMIN_LNG, name="Ali"):
    return {"name": name, "location": {"lat": lat, "lng": lng}}


def package_body(lat=ADMIN_LAT, lng=ADMIN_LNG):
    return {
        "pickup": {"lat": lat, "lng": lng, "address": "Pickup St"},
        "dropoff": {"lat": lat + 0.01, "lng": lng, "address": "Dropoff Ave"},
    }


def test_health(client):
    assert client.get("/health").json() == {"status": "ok"}


def test_admin_is_seeded_from_settings(client):
    body = client.get("/admin").json()
    assert body == {"name": "Test Admin", "location": {"lat": ADMIN_LAT, "lng": ADMIN_LNG}}


def test_update_admin(client):
    new = {"name": "HQ 2", "location": {"lat": 51.5, "lng": -0.12}}
    assert client.put("/admin", json=new).json() == new
    assert client.get("/admin").json() == new


def test_add_package_without_riders_waits(client):
    response = client.post("/packages", json=package_body())
    assert response.status_code == 201
    body = response.json()
    assert body["assignment"] is None
    assert body["package"]["status"] == "waiting"
    assert body["package"]["id"].startswith("pkg_")
    assert body["package"]["pickup"]["address"] == "Pickup St"


def test_add_package_pairs_with_nearest_rider(client):
    near = client.post("/riders", json=rider_body(ADMIN_LAT + ONE_MILE_LAT, name="near")).json()
    client.post("/riders", json=rider_body(ADMIN_LAT + ONE_MILE_LAT * 3, name="far"))

    body = client.post("/packages", json=package_body()).json()

    assert body["package"]["status"] == "assigned"
    assert body["assignment"]["rider_id"] == near["rider"]["id"]
    assert body["assignment"]["rider_name"] == "near"
    assert body["assignment"]["trigger"] == "package_added"

    state = client.get("/scheduler/state").json()
    assert [r["name"] for r in state["riders"]] == ["far"]
    assert state["packages"] == []


def test_add_rider_pairs_with_waiting_package(client):
    package = client.post("/packages", json=package_body()).json()["package"]
    body = client.post("/riders", json=rider_body()).json()
    assert body["rider"]["status"] == "assigned"
    assert body["assignment"]["package_id"] == package["id"]
    assert body["assignment"]["trigger"] == "rider_added"


def test_out_of_range_items_both_wait(client):
    client.post("/packages", json=package_body())
    body = client.post("/riders", json=rider_body(ADMIN_LAT + ONE_MILE_LAT * 6)).json()
    assert body["assignment"] is None

    state = client.get("/scheduler/state").json()
    assert len(state["packages"]) == 1 and len(state["riders"]) == 1
    assert state["radius_policy"]["initial_radius_miles"] == 5.0


def test_validation_rejects_bad_coordinates(client):
    assert client.post("/riders", json=rider_body(lat=91)).status_code == 422
    assert (
        client.post("/riders", json={"name": "", "location": {"lat": 0, "lng": 0}}).status_code
        == 422
    )
    assert client.post("/packages", json={"pickup": {"lat": 0, "lng": 0}}).status_code == 422


def test_get_and_list_filters(client):
    rider = client.post("/riders", json=rider_body()).json()["rider"]
    client.post("/packages", json=package_body())  # pairs with the rider
    waiting = client.post("/packages", json=package_body()).json()["package"]

    assert client.get(f"/riders/{rider['id']}").json()["status"] == "assigned"
    assert [p["id"] for p in client.get("/packages?status=waiting").json()] == [waiting["id"]]
    assert len(client.get("/packages").json()) == 2
    assert client.get("/riders?status=available").json() == []
    assert client.get("/packages/pkg_nope").status_code == 404
    assert client.get("/riders/rdr_nope").status_code == 404
    assert client.get("/packages?status=bogus").status_code == 422


def test_delete_package_and_rider(client):
    package = client.post("/packages", json=package_body()).json()["package"]
    assert client.delete(f"/packages/{package['id']}").status_code == 200
    assert client.delete(f"/packages/{package['id']}").status_code == 404

    rider = client.post("/riders", json=rider_body()).json()["rider"]
    assert client.delete(f"/riders/{rider['id']}").status_code == 200


def test_cannot_delete_assigned_items(client):
    rider = client.post("/riders", json=rider_body()).json()["rider"]
    package = client.post("/packages", json=package_body()).json()["package"]
    assert client.delete(f"/packages/{package['id']}").status_code == 409
    assert client.delete(f"/riders/{rider['id']}").status_code == 409


def test_assignments_history(client):
    for _ in range(3):
        client.post("/riders", json=rider_body())
        client.post("/packages", json=package_body())
    history = client.get("/assignments?limit=2").json()
    assert len(history) == 2
    assert history[0]["created_at"] >= history[1]["created_at"]
    assert client.get("/assignments?limit=0").status_code == 422


def test_simulate_spawns_requested_counts(client):
    body = client.post("/simulate", json={"packages": 6, "riders": 4, "radius_miles": 8}).json()
    assert len(body["packages"]) == 6
    assert len(body["riders"]) == 4
    assert len(body["assignments"]) <= 4

    state = client.get("/scheduler/state").json()
    assert len(state["packages"]) == 6 - len(body["assignments"])
    assert len(state["riders"]) == 4 - len(body["assignments"])


def test_simulate_validates_limits(client):
    assert client.post("/simulate", json={"packages": 51}).status_code == 422


def test_reset(client):
    client.post("/riders", json=rider_body())
    client.post("/packages", json=package_body())
    client.post("/packages", json=package_body())

    assert client.post("/scheduler/reset").status_code == 204

    state = client.get("/scheduler/state").json()
    assert state["packages"] == [] and state["riders"] == []
    assert client.get("/assignments").json() == []
    assert client.get("/admin").json()["name"] == "Test Admin"


def test_radius_policy_is_seeded_from_settings(client):
    assert client.get("/settings/radius").json() == {
        "initial_radius_miles": 5.0,
        "increment_miles": 0.0,
        "interval_seconds": 30.0,
        "max_radius_miles": 5.0,
    }


def test_update_radius_policy_pairs_packages_now_in_reach(client):
    client.post("/packages", json=package_body())
    client.post("/riders", json=rider_body(ADMIN_LAT + ONE_MILE_LAT * 8))
    assert len(client.get("/scheduler/state").json()["packages"]) == 1

    policy = {
        "initial_radius_miles": 10,
        "increment_miles": 1,
        "interval_seconds": 5,
        "max_radius_miles": 12,
    }
    assert client.put("/settings/radius", json=policy).json() == policy

    state = client.get("/scheduler/state").json()
    assert state["packages"] == [] and state["riders"] == []
    assert state["radius_policy"] == policy
    assert client.get("/assignments").json()[0]["trigger"] == "radius_expanded"


def test_update_radius_policy_validates(client):
    bad = {"initial_radius_miles": 5, "increment_miles": 2, "max_radius_miles": 3}
    assert client.put("/settings/radius", json=bad).status_code == 422
    assert client.put("/settings/radius", json={"interval_seconds": 0}).status_code == 422


def test_openapi_lists_all_routes(client):
    paths = client.get("/openapi.json").json()["paths"]
    for path in [
        "/admin",
        "/packages",
        "/riders",
        "/scheduler/state",
        "/assignments",
        "/simulate",
        "/settings/radius",
    ]:
        assert path in paths
