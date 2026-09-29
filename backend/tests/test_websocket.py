"""WebSocket event stream behaviour."""

from tests.conftest import ADMIN_LAT, ADMIN_LNG
from tests.test_api import package_body, rider_body


def test_first_message_is_snapshot(client):
    client.post("/packages", json=package_body())
    with client.websocket_connect("/ws/scheduler") as ws:
        event = ws.receive_json()
    assert event["type"] == "scheduler.snapshot"
    assert event["data"]["admin"]["location"] == {"lat": ADMIN_LAT, "lng": ADMIN_LNG}
    assert len(event["data"]["packages"]) == 1
    assert event["data"]["riders"] == []
    assert "timestamp" in event


def test_package_then_assignment_events(client):
    with client.websocket_connect("/ws/scheduler") as ws:
        ws.receive_json()  # snapshot

        rider = client.post("/riders", json=rider_body()).json()["rider"]
        added_rider = ws.receive_json()
        assert added_rider["type"] == "rider.added"
        assert added_rider["data"]["rider"]["id"] == rider["id"]

        package = client.post("/packages", json=package_body()).json()["package"]
        added = ws.receive_json()
        assert added["type"] == "package.added"
        assert added["data"]["package"]["status"] == "assigned"

        assigned = ws.receive_json()
        assert assigned["type"] == "assignment.created"
        assert assigned["data"]["assignment"]["package_id"] == package["id"]
        assert assigned["data"]["assignment"]["rider_id"] == rider["id"]


def test_removal_admin_and_reset_events(client):
    with client.websocket_connect("/ws/scheduler") as ws:
        ws.receive_json()

        package = client.post("/packages", json=package_body()).json()["package"]
        ws.receive_json()
        client.delete(f"/packages/{package['id']}")
        removed_package = ws.receive_json()
        assert removed_package["type"] == "package.removed"
        assert removed_package["data"] == {"package_id": package["id"]}

        rider = client.post("/riders", json=rider_body()).json()["rider"]
        ws.receive_json()
        client.delete(f"/riders/{rider['id']}")
        removed = ws.receive_json()
        assert removed["type"] == "rider.removed" and removed["data"] == {"rider_id": rider["id"]}

        client.put("/admin", json={"name": "HQ", "location": {"lat": 1, "lng": 2}})
        updated = ws.receive_json()
        assert updated["type"] == "admin.updated"
        assert updated["data"]["admin"]["name"] == "HQ"

        client.post("/scheduler/reset")
        assert ws.receive_json()["type"] == "scheduler.reset"


def test_events_fan_out_to_every_client(client):
    with (
        client.websocket_connect("/ws/scheduler") as a,
        client.websocket_connect("/ws/scheduler") as b,
    ):
        a.receive_json()
        b.receive_json()
        client.post("/riders", json=rider_body())
        assert a.receive_json()["type"] == "rider.added"
        assert b.receive_json()["type"] == "rider.added"


def test_ping_pong(client):
    with client.websocket_connect("/ws/scheduler") as ws:
        ws.receive_json()
        ws.send_text("ping")
        assert ws.receive_text() == "pong"


def test_disconnect_unsubscribes(client):
    with client.websocket_connect("/ws/scheduler") as ws:
        ws.receive_json()
        assert client.app.state.hub.subscriber_count == 1
    # Trigger a publish so the server notices the closed socket, then check cleanup.
    client.post("/riders", json=rider_body())
    assert client.app.state.hub.subscriber_count == 0
