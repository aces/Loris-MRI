from datetime import datetime, time
from decimal import Decimal

from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.models.physio_event_file as db_physio_event_file
import lib.db.models.physio_file as db_physio_file
from lib.db.base import Base


class DbPhysioTaskEvent(Base):
    __tablename__ = 'physiological_task_event'

    id             : Mapped[int]            = mapped_column('PhysiologicalTaskEventID', primary_key=True)
    physio_file_id : Mapped[int]            = mapped_column('PhysiologicalFileID', ForeignKey('physiological_file.PhysiologicalFileID'))
    event_file_id  : Mapped[int]            = mapped_column('EventFileID', ForeignKey('physiological_event_file.EventFileID'))
    insert_time    : Mapped[datetime]       = mapped_column('InsertTime')
    onset          : Mapped[Decimal]        = mapped_column('Onset')
    duration       : Mapped[Decimal]        = mapped_column('Duration')
    channel        : Mapped[str | None]     = mapped_column('Channel')
    event_code     : Mapped[int | None]     = mapped_column('EventCode')
    event_value    : Mapped[str | None]     = mapped_column('EventValue')
    event_sample   : Mapped[Decimal | None] = mapped_column('EventSample')
    event_type     : Mapped[str | None]     = mapped_column('EventType')
    trial_type     : Mapped[str | None]     = mapped_column('TrialType')
    response_time  : Mapped[time | None]    = mapped_column('ResponseTime')

    physio_file : Mapped['db_physio_file.DbPhysioFile']            = relationship('PhysiologicalFile')
    event_file  : Mapped['db_physio_event_file.DbPhysioEventFile'] = relationship('PhysiologicalEventFile', back_populates='task_events')
