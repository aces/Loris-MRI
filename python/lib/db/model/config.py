from typing import Optional

from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.model.config_setting as db_config_setting
from lib.db.base import Base


class DbConfig(Base):
    __tablename__ = 'Config'

    id         : Mapped[int]           = mapped_column('ID', primary_key=True)
    setting_id : Mapped[int]           = mapped_column('ConfigID', ForeignKey('ConfigSettings.ID'))
    value      : Mapped[Optional[str]] = mapped_column('Value')

    setting : Mapped['db_config_setting.DbConfigSetting'] = relationship('DbConfigSetting')
