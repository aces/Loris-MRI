from sqlalchemy.orm import Mapped, mapped_column

from lib.db.base import Base


class DbPermissionCategory(Base):
    __tablename__ = 'permissions_category'

    id          : Mapped[int] = mapped_column('ID', primary_key=True)
    description : Mapped[str] = mapped_column('Description')
