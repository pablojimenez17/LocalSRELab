import json
import logging
import math
import os
import sys
import time
from contextlib import asynccontextmanager
from typing import List, Optional

from fastapi import FastAPI, Depends, HTTPException, status, Query
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from sqlalchemy.orm import Session
from prometheus_fastapi_instrumentator import Instrumentator

from app.config import get_settings
from app.database import init_db, check_db_connection, get_db, Item
from app.cache import check_redis_connection, get_cache_value, set_cache_value

settings = get_settings()

# Configure structured JSON logging for Loki
class JsonFormatter(logging.Formatter):
    def format(self, record):
        log_obj = {
            "timestamp": self.formatTime(record, self.datefmt),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            "pod_name": os.getenv("HOSTNAME", "local-host"),
        }
        if record.exc_info:
            log_obj["exception"] = self.formatException(record.exc_info)
        return json.dumps(log_obj)

handler = logging.StreamHandler(sys.stdout)
handler.setFormatter(JsonFormatter())
root_logger = logging.getLogger()
root_logger.setLevel(logging.INFO)
root_logger.handlers = [handler]
logger = logging.getLogger("localsre.api")

# Chaos injection state
chaos_state = {
    "forced_unready": False,
    "unready_until": 0.0
}


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Initializing LocalSRE API service...")
    init_db()
    yield
    logger.info("Shutting down LocalSRE API service...")


app = FastAPI(
    title="LocalSRE Lab API",
    description="Production-grade API for SRE & Kubernetes observability, resilience and chaos engineering.",
    version="1.0.0",
    lifespan=lifespan
)

# Prometheus Metrics Instrumentation
instrumentator = Instrumentator(
    should_group_status_codes=False,
    should_ignore_untemplated=True,
    should_respect_env_var=True,
    env_var_name="ENABLE_METRICS",
    excluded_handlers=["/metrics", "/healthz"]
)
instrumentator.instrument(app).expose(app, endpoint="/metrics")


# Pydantic Schemas
class ItemCreate(BaseModel):
    title: str
    description: Optional[str] = None


class ItemResponse(BaseModel):
    id: int
    title: str
    description: Optional[str]
    created_at: Optional[str]

    class Config:
        from_attributes = True


# ==========================================================
# SRE Probes (Kubernetes Liveness & Readiness)
# ==========================================================

@app.get("/healthz", tags=["Probes"], summary="Liveness Probe")
def healthz():
    """Returns 200 if container process is alive."""
    return {"status": "alive", "timestamp": time.time(), "pod": os.getenv("HOSTNAME", "local")}


@app.get("/readyz", tags=["Probes"], summary="Readiness Probe")
def readyz():
    """
    Returns 200 if dependencies (PostgreSQL, Redis) are healthy and pod can receive traffic.
    Returns 503 if degraded, causing Kubernetes Service to remove pod from Endpoints.
    """
    current_time = time.time()
    if chaos_state["forced_unready"] and current_time < chaos_state["unready_until"]:
        logger.warning("Readiness probe failing due to active chaos experiment: forced_unready")
        return JSONResponse(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            content={"status": "degraded", "reason": "chaos_forced_unready", "pod": os.getenv("HOSTNAME", "local")}
        )

    db_healthy = check_db_connection()
    redis_healthy = check_redis_connection()

    if not db_healthy or not redis_healthy:
        logger.error(f"Readiness check degraded: db={db_healthy}, redis={redis_healthy}")
        return JSONResponse(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            content={
                "status": "degraded",
                "database": "up" if db_healthy else "down",
                "redis": "up" if redis_healthy else "down",
                "pod": os.getenv("HOSTNAME", "local")
            }
        )

    return {
        "status": "ready",
        "database": "connected",
        "redis": "connected",
        "pod": os.getenv("HOSTNAME", "local")
    }


# ==========================================================
# Business Endpoints (RED Metrics: Rate, Errors, Duration)
# ==========================================================

@app.get("/", tags=["Info"])
def root():
    return {
        "lab": "LocalSRE Lab",
        "architecture": "FastAPI + Redis + PostgreSQL on Kubernetes",
        "pod": os.getenv("HOSTNAME", "local"),
        "docs": "/docs",
        "metrics": "/metrics"
    }


@app.post("/items", response_model=ItemResponse, status_code=status.HTTP_201_CREATED, tags=["Items"])
def create_item(payload: ItemCreate, db: Session = Depends(get_db)):
    logger.info(f"Creating new item with title: {payload.title}")
    new_item = Item(title=payload.title, description=payload.description)
    db.add(new_item)
    db.commit()
    db.refresh(new_item)

    # Invalidate cached list
    set_cache_value("items:all", "", ttl_seconds=1)

    return ItemResponse(
        id=new_item.id,
        title=new_item.title,
        description=new_item.description,
        created_at=new_item.created_at.isoformat() if new_item.created_at else None
    )


@app.get("/items", response_model=List[ItemResponse], tags=["Items"])
def list_items(db: Session = Depends(get_db)):
    cached_data = get_cache_value("items:all")
    if cached_data:
        try:
            return json.loads(cached_data)
        except Exception:
            pass

    items = db.query(Item).order_by(Item.id.desc()).limit(100).all()
    results = [
        ItemResponse(
            id=item.id,
            title=item.title,
            description=item.description,
            created_at=item.created_at.isoformat() if item.created_at else None
        ).model_dump()
        for item in items
    ]

    set_cache_value("items:all", json.dumps(results), ttl_seconds=15)
    return results


@app.get("/items/{item_id}", response_model=ItemResponse, tags=["Items"])
def get_item(item_id: int, db: Session = Depends(get_db)):
    cached = get_cache_value(f"item:{item_id}")
    if cached:
        try:
            return json.loads(cached)
        except Exception:
            pass

    item = db.query(Item).filter(Item.id == item_id).first()
    if not item:
        logger.warning(f"Item not found: {item_id}")
        raise HTTPException(status_code=404, detail="Item not found")

    result = ItemResponse(
        id=item.id,
        title=item.title,
        description=item.description,
        created_at=item.created_at.isoformat() if item.created_at else None
    ).model_dump()

    set_cache_value(f"item:{item_id}", json.dumps(result), ttl_seconds=30)
    return result


# ==========================================================
# Chaos Engineering Endpoints (Incident Simulation)
# ==========================================================

@app.post("/chaos/cpu-stress", tags=["Chaos Testing"])
def chaos_cpu_stress(duration_seconds: int = Query(default=5, ge=1, le=60)):
    """
    Intentionally burns CPU cycles for N seconds.
    Demonstrates Kubernetes Horizontal Pod Autoscaler (HPA) CPU threshold triggering.
    """
    logger.warning(f"Starting CPU stress chaos experiment for {duration_seconds} seconds")
    start = time.time()
    count = 0
    while time.time() - start < duration_seconds:
        # Intensive computation
        _ = math.sqrt(math.factorial(200) + count)
        count += 1

    logger.info(f"Completed CPU stress run with {count} iterations")
    return {
        "experiment": "cpu-stress",
        "status": "completed",
        "duration_seconds": duration_seconds,
        "iterations": count,
        "pod": os.getenv("HOSTNAME", "local")
    }


@app.get("/chaos/error-spike", tags=["Chaos Testing"])
def chaos_error_spike(error_rate: float = Query(default=1.0, ge=0.0, le=1.0)):
    """
    Simulates HTTP 500 error spikes to trigger Prometheus Alerting & Grafana Error Rate panels.
    """
    import random
    if random.random() < error_rate:
        logger.error("Chaos error injection: Simulated HTTP 500 Internal Server Error")
        raise HTTPException(status_code=500, detail="Chaos simulated internal error")
    return {"status": "ok", "message": "Request succeeded despite chaos probability check"}


@app.post("/chaos/unready", tags=["Chaos Testing"])
def chaos_unready(duration_seconds: int = Query(default=30, ge=5, le=300)):
    """
    Forces the pod into an unready state for N seconds.
    Demonstrates Kubernetes removing the pod from Service Endpoints without killing it.
    """
    chaos_state["forced_unready"] = True
    chaos_state["unready_until"] = time.time() + duration_seconds
    logger.warning(f"Pod forced UNREADY for {duration_seconds}s. Next /readyz calls will return 503.")
    return {
        "experiment": "unready",
        "forced_unready": True,
        "duration_seconds": duration_seconds,
        "pod": os.getenv("HOSTNAME", "local")
    }


@app.post("/chaos/ready", tags=["Chaos Testing"])
def chaos_ready_reset():
    """Resets the unready chaos state immediately."""
    chaos_state["forced_unready"] = False
    chaos_state["unready_until"] = 0.0
    logger.info("Resetting forced_unready status to normal.")
    return {"experiment": "ready", "status": "restored", "pod": os.getenv("HOSTNAME", "local")}
