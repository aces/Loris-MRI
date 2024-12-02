from sqlalchemy import select, update
from sqlalchemy.orm import Session as Database

from lib.db.model.config import DbConfig
from lib.db.model.config_setting import DbConfigSetting


def get_config_with_setting_name(db: Database, name: str):
    """
    Get a single configuration entry from the database using its configuration setting name, or
    raise an exception if no entry or several entries are found.
    """

    return db.execute(select(DbConfig)
        .join(DbConfig.setting)
        .where(DbConfigSetting.name == name)
    ).scalar_one()


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
