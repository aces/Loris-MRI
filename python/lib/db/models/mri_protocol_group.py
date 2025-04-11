from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.models.mri_protocol_violated_scan as db_mri_protocol_violated_scan
from lib.db.base import Base


class DbMriProtocolGroup(Base):
    __tablename__ = 'mri_protocol_group'

    id   : Mapped[int] = mapped_column('MriProtocolGroupID', primary_key=True)
    name : Mapped[str] = mapped_column('Name')

    violated_scans: Mapped['db_mri_protocol_violated_scan.DbMriProtocolViolatedScan'] \
        = relationship('DbMriProtocolViolatedScan', back_populates='protocol_group')
