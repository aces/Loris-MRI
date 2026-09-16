from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.models.module as db_module
import lib.db.models.permission_category as db_permission_category
from lib.db.base import Base


class DbPermission(Base):
    __tablename__ = 'permissions'

    id          : Mapped[int]        = mapped_column('permID', primary_key=True)
    code        : Mapped[str]        = mapped_column('code', default='', unique=True)
    description : Mapped[str]        = mapped_column('description', default='')
    module_id   : Mapped[int | None] = mapped_column('moduleID', ForeignKey('modules.ID'))
    category_id : Mapped[int]        = mapped_column('categoryID', ForeignKey('permissions_category.ID'), default=2)

    module   : Mapped['db_module.DbModule | None']                   = relationship('DbModule', back_populates='permissions')
    category : Mapped['db_permission_category.DbPermissionCategory'] = relationship('DbPermissionCategory')
