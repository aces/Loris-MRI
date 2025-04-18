from decimal import Decimal

from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.models.mri_protocol_check_group as db_mri_protocol_check_group
import lib.db.models.mri_scan_type as db_mri_scan_type
from lib.db.base import Base


class DbMriProtocolCheck(Base):
    __tablename__ = 'mri_protocol_checks'

    id                      : Mapped[int]            = mapped_column('ID', primary_key=True)
    scan_type_id            : Mapped[int | None] \
        = mapped_column('MriScanTypeID', ForeignKey('mri_scan_type.MriScanTypeID'))
    severity                : Mapped[str | None]     = mapped_column('Severity')
    header                  : Mapped[str | None]     = mapped_column('Header')
    valid_min               : Mapped[Decimal | None] = mapped_column('ValidMin')
    valid_max               : Mapped[Decimal | None] = mapped_column('ValidMax')
    valid_regex             : Mapped[str | None]     = mapped_column('ValidRegex')
    protocol_check_group_id : Mapped[int] \
        = mapped_column('MriProtocolChecksGroupID', ForeignKey('mri_protocol_checks_group.MriProtocolChecksGroupID'))

    scan_type            : Mapped['db_mri_scan_type.DbMriScanType'] \
        = relationship('DbMriScanType', back_populates='protocol_checks')
    protocol_check_group: Mapped['db_mri_protocol_check_group.DbMriProtocolCheckGroup'] \
        = relationship('DbMriProtocolCheckGroup', back_populates='protocol_check')
