from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.models.mri_protocol_check as db_mri_protocol_check
import lib.db.models.mri_scan_validation_error as db_mri_scan_validation_error
from lib.db.base import Base


class DbMriScanType(Base):
    __tablename__ = 'mri_scan_type'

    id   : Mapped[int] = mapped_column('MriScanTypeID', primary_key=True)
    name : Mapped[str] = mapped_column('MriScanTypeName')

    protocol_checks : Mapped[list['db_mri_protocol_check.DbMriProtocolCheck']] \
        = relationship('DbMriProtocolCheck', back_populates='scan_type')
    scan_validation_errors: Mapped[list['db_mri_scan_validation_error.DbMriScanValidationError']] \
        = relationship('DbMriScanValidationError', back_populates='scan_type')
