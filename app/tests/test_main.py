import pytest
from fastapi.testclient import TestClient
from unittest.mock import patch

from app.main import app

client = TestClient(app)


def test_root_endpoint():
    response = client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert data["lab"] == "LocalSRE Lab"
    assert "/metrics" in data["metrics"]


def test_healthz_liveness_probe():
    response = client.get("/healthz")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "alive"


def test_readyz_healthy():
    with patch("app.main.check_db_connection", return_value=True), \
         patch("app.main.check_redis_connection", return_value=True):
        response = client.get("/readyz")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "ready"
        assert data["database"] == "connected"
        assert data["redis"] == "connected"


def test_readyz_degraded_db():
    with patch("app.main.check_db_connection", return_value=False), \
         patch("app.main.check_redis_connection", return_value=True):
        response = client.get("/readyz")
        assert response.status_code == 503
        data = response.json()
        assert data["status"] == "degraded"
        assert data["database"] == "down"


def test_readyz_degraded_redis():
    with patch("app.main.check_db_connection", return_value=True), \
         patch("app.main.check_redis_connection", return_value=False):
        response = client.get("/readyz")
        assert response.status_code == 503
        data = response.json()
        assert data["status"] == "degraded"
        assert data["redis"] == "down"


def test_metrics_prometheus_endpoint():
    response = client.get("/metrics")
    assert response.status_code == 200
    assert "http_requests_total" in response.text or "http_request_duration_seconds" in response.text or "# HELP" in response.text


def test_chaos_error_spike_always_fails():
    response = client.get("/chaos/error-spike?error_rate=1.0")
    assert response.status_code == 500


def test_chaos_error_spike_never_fails():
    response = client.get("/chaos/error-spike?error_rate=0.0")
    assert response.status_code == 200


def test_chaos_cpu_stress():
    response = client.post("/chaos/cpu-stress?duration_seconds=1")
    assert response.status_code == 200
    data = response.json()
    assert data["experiment"] == "cpu-stress"
    assert data["status"] == "completed"


def test_chaos_unready_lifecycle():
    # Force unready
    resp_unready = client.post("/chaos/unready?duration_seconds=10")
    assert resp_unready.status_code == 200
    assert resp_unready.json()["forced_unready"] is True

    # Check that readyz returns 503 while forced unready
    resp_probe = client.get("/readyz")
    assert resp_probe.status_code == 503
    assert resp_probe.json()["reason"] == "chaos_forced_unready"

    # Reset back to ready
    resp_ready = client.post("/chaos/ready")
    assert resp_ready.status_code == 200
    assert resp_ready.json()["status"] == "restored"
