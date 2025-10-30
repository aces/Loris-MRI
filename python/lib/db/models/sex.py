from sqlalchemy.orm import Mapped, mapped_column

from lib.db.base import Base


class DbSex(Base):
    __tablename__ = 'sex'

    name : Mapped[str] = mapped_column('Name', primary_key=True)
