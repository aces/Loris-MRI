from sqlalchemy.orm import Mapped, mapped_column

from lib.db.base import Base


class DbBidsScanTypeSubcategory(Base):
    __tablename__ = 'bids_scan_type_subcategory'

    id   : Mapped[int] = mapped_column('BIDSScanTypeSubCategoryID', primary_key=True)
    name : Mapped[str] = mapped_column('BIDSScanTypeSubCategory', unique=True)
