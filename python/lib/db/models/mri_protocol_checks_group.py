from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.models.mri_violations_log as db_mri_violations_log
from lib.db.base import Base


class DbMriProtocolChecksGroup(Base):
    __tablename__ = 'mri_protocol_checks_group'

    id   : Mapped[int] = mapped_column('MriProtocolChecksGroupID', primary_key=True)
    name : Mapped[str] = mapped_column('Name')

    violations_log: Mapped['db_mri_violations_log.DbMriViolationsLog'] \
        = relationship('DbMriViolationsLog', back_populates='protocol_checks_group')
