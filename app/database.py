import logging
from sqlalchemy import create_engine, Column, Integer, String, DateTime, text
from sqlalchemy.orm import declarative_base, sessionmaker
from datetime import datetime
from app.config import get_settings

logger = logging.getLogger("localsre.database")
settings = get_settings()

engine = create_engine(
    settings.database_url,
    pool_pre_ping=True,
    pool_size=10,
    max_overflow=20,
    connect_args={"connect_timeout": 3}
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


class Item(Base):
    __tablename__ = "items"

    id = Column(Integer, primary_key=True, index=True)
    title = Column(String(120), nullable=False)
    description = Column(String(255), nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)


def init_db():
    try:
        Base.metadata.create_all(bind=engine)
        logger.info("Database schema initialized successfully")
    except Exception as exc:
        logger.warning(f"Could not initialize database tables: {exc}")


def check_db_connection() -> bool:
    """Readiness probe helper to check Postgres connection"""
    try:
        with engine.connect() as connection:
            connection.execute(text("SELECT 1"))
        return True
    except Exception as exc:
        logger.error(f"Database readiness check failed: {exc}")
        return False


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
