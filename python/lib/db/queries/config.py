from sqlalchemy import select, update
from sqlalchemy.orm import Session as Database

from lib.db.models.config import DbConfig
from lib.db.models.config_setting import DbConfigSetting


def try_get_config_with_setting_name(db: Database, name: str) -> DbConfig | None:
    """
    Try to get a single configuration entry from the database using its configuration setting name,
    or return `None` if no configuration setting is found.
    """

    return db.execute(select(DbConfig)
        .join(DbConfig.setting)
        .where(DbConfigSetting.name == name)
    ).scalar_one_or_none()


def set_config_with_setting_name(db: Database, name: str, value: str):
    """
    Set a single configuration entry from the database using its configuration setting name, or
    raise an exception if the configuration setting is not found.
    """

    config_setting = db.execute(select(DbConfigSetting)
        .where(DbConfigSetting.name == name)
    ).scalar_one()

    db.execute(update(DbConfig)
        .where(DbConfig.setting == config_setting)
        .values(value = value)
    )
