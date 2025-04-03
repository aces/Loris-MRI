from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.models.mri_protocol_checks_group as db_mri_protocol_checks_group
import lib.db.models.mri_scan_type as db_mri_scan_type
import lib.db.models.mri_violations_log as db_mri_violations_log
from lib.db.base import Base


class DbMriProtocolChecks(Base):
    __tablename__ = 'mri_protocol_checks'

    id                          : Mapped[int]          = mapped_column('ID', primary_key=True)
    mri_scan_type_id            : Mapped[int | None]   \
        = mapped_column('MriScanTypeID', ForeignKey('mri_scan_type.MriScanTypeID'))
    severity                    : Mapped[str | None]   = mapped_column('Severity')
    header                      : Mapped[str | None]   = mapped_column('Header')
    valid_min                   : Mapped[float | None] = mapped_column('ValidMin')
    valid_max                   : Mapped[float | None] = mapped_column('ValidMax')
    valid_regex                 : Mapped[float | None] = mapped_column('ValidRegex')
    mri_protocol_group_check_id : Mapped[int | None]   \
        = mapped_column('MriProtocolChecksGroupID', ForeignKey('mri_protocol_checks_group.MriProtocolChecksGroupID'))

    scan_type            : Mapped['db_mri_scan_type.DbMriScanType'] \
        = relationship('DbMriScanType', back_populates='protocol_checks')
    protocol_checks_group: Mapped['db_mri_protocol_checks_group.DbMriProtocolChecksGroup'] \
        = relationship('DbMriProtocolChecksGroup', back_populates='protocol_checks')
    violations_log       : Mapped['db_mri_violations_log.DbMriViolationsLog'] \
        = relationship('DbMriViolationsLog', back_populates='protocol_checks')