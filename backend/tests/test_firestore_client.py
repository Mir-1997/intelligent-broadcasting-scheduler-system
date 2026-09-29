"""create_firestore_client chooses emulator vs real-project credentials correctly."""

import os

import pytest

from broadcast_scheduler.config import Settings
from broadcast_scheduler.repositories import firestore as fs


@pytest.fixture
def captured(monkeypatch):
    calls = {}

    class FakeClient:
        def __init__(self, **kwargs):
            calls.update(kwargs)

    monkeypatch.setattr(fs, "AsyncClient", FakeClient)
    monkeypatch.setattr(
        fs.service_account.Credentials,
        "from_service_account_file",
        staticmethod(lambda path: f"creds-from:{path}"),
    )
    monkeypatch.delenv("FIRESTORE_EMULATOR_HOST", raising=False)
    return calls


def test_emulator_ignores_credentials(captured):
    fs.create_firestore_client(
        Settings(firestore_emulator_host="localhost:9999", google_application_credentials="/k.json")
    )
    assert os.environ["FIRESTORE_EMULATOR_HOST"] == "localhost:9999"
    assert captured["credentials"] is None


def test_real_project_loads_key_file(captured):
    fs.create_firestore_client(
        Settings(
            firestore_emulator_host="",
            gcp_project_id="my-project",
            firestore_database="scheduler",
            google_application_credentials="/k.json",
        )
    )
    assert "FIRESTORE_EMULATOR_HOST" not in os.environ
    assert captured == {
        "project": "my-project",
        "credentials": "creds-from:/k.json",
        "database": "scheduler",
    }


def test_real_project_without_key_uses_adc(captured):
    fs.create_firestore_client(
        Settings(firestore_emulator_host="", google_application_credentials=None)
    )
    assert captured["credentials"] is None


def test_dotenv_beats_shell_environment(tmp_path, monkeypatch):
    env_file = tmp_path / ".env"
    env_file.write_text("GCP_PROJECT_ID=from-dotenv\nCOLLECTION_PREFIX=ibs_\n")
    monkeypatch.setenv("GCP_PROJECT_ID", "from-shell")
    monkeypatch.setenv("MAX_MATCH_RADIUS_MILES", "7")

    settings = Settings(_env_file=env_file)

    assert settings.gcp_project_id == "from-dotenv"  # .env wins
    assert settings.collection_prefix == "ibs_"
    assert settings.max_match_radius_miles == 7  # env still applies when .env is silent
