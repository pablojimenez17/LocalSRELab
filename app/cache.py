import logging
import redis
from app.config import get_settings

logger = logging.getLogger("localsre.cache")
settings = get_settings()

redis_client = redis.Redis(
    host=settings.redis_host,
    port=settings.redis_port,
    password=settings.redis_password if settings.redis_password else None,
    socket_connect_timeout=2,
    socket_timeout=2,
    decode_responses=True
)


def check_redis_connection() -> bool:
    """Readiness probe helper to check Redis connection"""
    try:
        return redis_client.ping()
    except Exception as exc:
        logger.error(f"Redis readiness check failed: {exc}")
        return False


def get_cache_value(key: str) -> str | None:
    try:
        return redis_client.get(key)
    except Exception as exc:
        logger.warning(f"Failed to read from cache key {key}: {exc}")
        return None


def set_cache_value(key: str, value: str, ttl_seconds: int = 60) -> bool:
    try:
        redis_client.setex(key, ttl_seconds, value)
        return True
    except Exception as exc:
        logger.warning(f"Failed to write to cache key {key}: {exc}")
        return False
