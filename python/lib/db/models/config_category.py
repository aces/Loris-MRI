from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.models.config_setting as db_config_setting
from lib.db.base import Base
from lib.db.decorators.int_bool import IntBool


class DbConfigCategory(Base):
    __tablename__ = 'ConfigCategories'

    id           : Mapped[int]         = mapped_column('ID', primary_key=True)
    name         : Mapped[str]         = mapped_column('Name')
    description  : Mapped[str | None]  = mapped_column('Description')
    visible      : Mapped[bool | None] = mapped_column('Visible', IntBool, default=False)
    label        : Mapped[str | None]  = mapped_column('Label')
    order_number : Mapped[int | None]  = mapped_column('OrderNumber')

    settings: Mapped[list['db_config_setting.DbConfigSetting']] = relationship('DbConfigSetting', back_populates='category')
