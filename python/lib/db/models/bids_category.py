from sqlalchemy.orm import Mapped, mapped_column

from lib.db.base import Base


class DbBidsCategory(Base):
    __tablename__ = 'bids_category'

    id   : Mapped[int] = mapped_column('BIDSCategoryID', primary_key=True)
    name : Mapped[str] = mapped_column('BIDSCategoryName', unique=True)
