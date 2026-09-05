from pydantic_settings import BaseSettings
from functools import lru_cache


class Settings(BaseSettings):
    app_name: str = "LocalSRE API"
    environment: str = "local"
    debug: bool = False
    port: int = 8000

    # PostgreSQL
    db_host: str = "localhost"
    db_port: int = 5432
    db_name: str = "localsredb"
    db_user: str = "sreuser"
    db_password: str = "change-me-sre-password"

    # Redis
    redis_host: str = "localhost"
    redis_port: int = 6379
    redis_password: str = ""

    # Chaos testing flag
    enable_chaos_endpoints: bool = True

    @property
    def database_url(self) -> str:
        return f"postgresql://{self.db_user}:{self.db_password}@{self.db_host}:{self.db_port}/{self.db_name}"

    class Config:
        env_file = ".env"
        extra = "ignore"


@lru_cache()
def get_settings() -> Settings:
    return Settings()
