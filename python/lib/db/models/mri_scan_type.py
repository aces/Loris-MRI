from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.models.mri_violations_log as db_mri_violations_log
from lib.db.base import Base


class DbMriScanType(Base):
    __tablename__ = 'mri_scan_type'

    id   : Mapped[int] = mapped_column('MriScanTypeID', primary_key=True)
    name : Mapped[str] = mapped_column('MriScanTypeName')

    violations_log: Mapped['db_mri_violations_log.DbMriViolationsLog'] \
        = relationship('DbMriViolationsLog', back_populates='scan_type')
