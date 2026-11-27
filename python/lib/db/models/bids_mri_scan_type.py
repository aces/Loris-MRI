from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.models.bids_category as db_bids_category
import lib.db.models.bids_phase_encoding_direction as db_bids_phase_encoding_direction
import lib.db.models.bids_scan_type as db_bids_scan_type
import lib.db.models.bids_scan_type_subcategory as db_bids_scan_type_subcategory
import lib.db.models.mri_scan_type as db_mri_scan_type
from lib.db.base import Base


class DbBidsMriScanType(Base):
    __tablename__ = 'bids_mri_scan_type_rel'

    scan_type_id                : Mapped[int]        = mapped_column('MRIScanTypeID', ForeignKey('mri_scan_type.MriScanTypeID'), primary_key=True, autoincrement=False)
    category_id                 : Mapped[int | None] = mapped_column('BIDSCategoryID', ForeignKey('bids_category.BIDSCategoryID'))
    subcategory_id              : Mapped[int | None] = mapped_column('BIDSScanTypeSubCategoryID', ForeignKey('bids_scan_type_subcategory.BIDSScanTypeSubCategoryID'))
    bids_scan_type_id           : Mapped[int | None] = mapped_column('BIDSScanTypeID', ForeignKey('bids_scan_type.BIDSScanTypeID'))
    echo_number                 : Mapped[int | None] = mapped_column('BIDSEchoNumber')
    phase_encoding_direction_id : Mapped[int | None] = mapped_column('BIDSPhaseEncodingDirectionID', ForeignKey('bids_phase_encoding_direction.BIDSPhaseEncodingDirectionID'))

    scan_type                : Mapped['db_mri_scan_type.DbMriScanType'] \
        = relationship('DbMriScanType')
    category                 : Mapped['db_bids_category.DbBidsCategory | None'] \
        = relationship('DbBidsCategory')
    subcategory              : Mapped['db_bids_scan_type_subcategory.DbBidsScanTypeSubcategory | None'] \
        = relationship('DbBidsScanTypeSubcategory')
    bids_scan_type           : Mapped['db_bids_scan_type.DbBidsScanType | None'] \
        = relationship('DbBidsScanType')
    phase_encoding_direction : Mapped['db_bids_phase_encoding_direction.DbBidsPhaseEncodingDirection | None'] \
        = relationship('DbBidsPhaseEncodingDirection')
