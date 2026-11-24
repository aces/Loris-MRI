from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.models.mri_protocol_check as db_mri_protocol_check
import lib.db.models.mri_scan_validation_error as db_mri_scan_validation_error
from lib.db.base import Base


class DbMriProtocolCheckGroup(Base):
    __tablename__ = 'mri_protocol_checks_group'

    id  : Mapped[int] = mapped_column('MriProtocolChecksGroupID', primary_key=True)
    name: Mapped[str] = mapped_column('Name')

    protocol_check: Mapped['db_mri_protocol_check.DbMriProtocolCheck'] \
        = relationship('DbMriProtocolCheck', back_populates='protocol_check_group')
    scan_validation_errors: Mapped['db_mri_scan_validation_error.DbMriScanValidationError'] \
        = relationship('DbMriScanValidationError', back_populates='protocol_check_group')
