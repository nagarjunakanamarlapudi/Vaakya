from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from vaakya.config import settings

engine = create_async_engine(settings.database_url, echo=(settings.vaakya_env == "dev"))
async_session = async_sessionmaker(engine, expire_on_commit=False)
