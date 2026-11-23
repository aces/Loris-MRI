from sqlalchemy.orm import Mapped, mapped_column

from lib.db.base import Base


class DbBidsScanType(Base):
    __tablename__ = 'bids_scan_type'

    id   : Mapped[int] = mapped_column('BIDSScanTypeID', primary_key=True)
    name : Mapped[str] = mapped_column('BIDSScanType', unique=True)
