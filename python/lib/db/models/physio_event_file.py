from datetime import datetime
from pathlib import Path

from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.models.imaging_file_type as db_imaging_file_type
import lib.db.models.physio_event_parameter as db_physio_event_parameter
import lib.db.models.physio_file as db_physio_file
import lib.db.models.physio_task_event as db_physio_task_event
import lib.db.models.project as db_project
from lib.db.base import Base
from lib.db.decorators.string_path import StringPath


class DbPhysioEventFile(Base):
    __tablename__ = 'physiological_event_file'

    id             : Mapped[int]         = mapped_column('EventFileID', primary_key=True)
    physio_file_id : Mapped[int | None]  = mapped_column('PhysiologicalFileID', ForeignKey('physiological_file.PhysiologicalFileID'))
    project_id     : Mapped[int | None]  = mapped_column('ProjectID', ForeignKey('Project.ProjectID'))
    file_type      : Mapped[str]         = mapped_column('FileType', ForeignKey('ImagingFileTypes.type'))
    file_path      : Mapped[Path | None] = mapped_column('FilePath', StringPath)
    last_update    : Mapped[datetime]    = mapped_column('LastUpdate')
    last_written   : Mapped[datetime]    = mapped_column('LastWritten')

    physio_file       : Mapped['db_physio_file.DbPhysioFile | None']                     = relationship('PhysiologicalFile')
    project           : Mapped['db_project.DbProject | None']                            = relationship('Project')
    imaging_file_type : Mapped['db_imaging_file_type.DbImagingFileType | None']          = relationship('ImagingFileTypes')
    task_events       : Mapped[list['db_physio_task_event.DbPhysioTaskEvent']]           = relationship('PhysiologicalTaskEvent', back_populates='event_file')
    event_parameters  : Mapped[list['db_physio_event_parameter.DbPhysioEventParameter']] = relationship('PhysiologicalEventParameter', back_populates='event_file')
