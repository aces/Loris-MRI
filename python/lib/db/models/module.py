from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.models.permission as db_permission
from lib.db.base import Base
from lib.db.decorators.y_n_bool import YNBool


class DbModule(Base):
    __tablename__ = 'modules'

    id     : Mapped[int]  = mapped_column('ID', primary_key=True)
    name   : Mapped[str]  = mapped_column('Name', unique=True)
    active : Mapped[bool] = mapped_column('Active', YNBool)

    permissions: Mapped[list['db_permission.DbPermission']] = relationship('DbPermission', back_populates='module')
