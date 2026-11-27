from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.models.mri_scan_classification_error as db_mri_scan_classification_error
from lib.db.base import Base


class DbMriProtocolGroup(Base):
    __tablename__ = 'mri_protocol_group'

    id   : Mapped[int] = mapped_column('MriProtocolGroupID', primary_key=True)
    name : Mapped[str] = mapped_column('Name')

    scan_classification_errors: Mapped['db_mri_scan_classification_error.DbMriScanClassificationError'] \
        = relationship('DbMriScanClassificationError', back_populates='protocol_group')
