from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.models.physio_task_event as db_physio_task_event
from lib.db.base import Base


class DbPhysioTaskEventOpt(Base):
    __tablename__ = 'physiological_task_event_opt'

    id             : Mapped[int]        = mapped_column('ID', primary_key=True)
    task_event_id  : Mapped[int]        = mapped_column('PhysiologicalTaskEventID', ForeignKey('physiological_task_event.PhysiologicalTaskEventID'))
    property_name  : Mapped[str]        = mapped_column('PropertyName')
    property_value : Mapped[str | None] = mapped_column('PropertyValue')

    task_event: Mapped['db_physio_task_event.DbPhysioTaskEvent'] = relationship('DbPhysioTaskEvent')
