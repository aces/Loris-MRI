from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.models.mri_protocol_check as db_mri_protocol_check
import lib.db.models.mri_violation_log as db_mri_violation_log
from lib.db.base import Base


class DbMriProtocolCheckGroup(Base):
    __tablename__ = 'mri_protocol_checks_group'

    id  : Mapped[int] = mapped_column('MriProtocolChecksGroupID', primary_key=True)
    name: Mapped[str] = mapped_column('Name')

    protocol_check: Mapped['db_mri_protocol_check.DbMriProtocolCheck'] \
        = relationship('DbMriProtocolCheck', back_populates='protocol_check_group')
    violations_log: Mapped['db_mri_violation_log.DbMriViolationLog'] \
        = relationship('DbMriViolationLog', back_populates='protocol_check_group')
