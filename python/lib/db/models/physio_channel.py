from datetime import datetime
from decimal import Decimal

from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.models.physio_channel_type as db_physio_channel_type
import lib.db.models.physio_file as db_physio_file
import lib.db.models.physio_status_type as db_physio_status_type
from lib.db.base import Base


class DbPhysioChannel(Base):
    __tablename__ = 'physiological_channel'

    id                 : Mapped[int]            = mapped_column('PhysiologicalChannelID', primary_key=True)
    physio_file_id     : Mapped[int]            = mapped_column('PhysiologicalFileID', ForeignKey('physiological_file.PhysiologicalFileID'))
    channel_type_id    : Mapped[int]            = mapped_column('PhysiologicalChannelTypeID', ForeignKey('physiological_channel_type.PhysiologicalChannelTypeID'))
    status_type_id     : Mapped[int | None]     = mapped_column('PhysiologicalStatusTypeID', ForeignKey('physiological_status_type.PhysiologicalStatusTypeID'))
    insert_time        : Mapped[datetime]       = mapped_column('InsertTime', default=datetime.now)
    name               : Mapped[str]            = mapped_column('Name')
    description        : Mapped[str | None]     = mapped_column('Description')
    sampling_frequency : Mapped[int | None]     = mapped_column('SamplingFrequency')
    low_cutoff         : Mapped[Decimal | None] = mapped_column('LowCutoff')
    high_cutoff        : Mapped[Decimal | None] = mapped_column('HighCutoff')
    manual_flag        : Mapped[Decimal | None] = mapped_column('ManualFlag')
    notch              : Mapped[int | None]     = mapped_column('Notch')
    reference          : Mapped[str | None]     = mapped_column('Reference')
    status_description : Mapped[str | None]     = mapped_column('StatusDescription')
    unit               : Mapped[str | None]     = mapped_column('Unit')
    file_path          : Mapped[str | None]     = mapped_column('FilePath')

    physio_file  : Mapped['db_physio_file.DbPhysioFile']                = relationship('DbPhysioFile', back_populates='channels')
    channel_type : Mapped['db_physio_channel_type.DbPhysioChannelType'] = relationship('DbPhysioChannelType')
    status_type  : Mapped['db_physio_status_type.DbPhysioStatusType']   = relationship('DbPhysioStatusType')
