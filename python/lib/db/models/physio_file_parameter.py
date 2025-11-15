from datetime import datetime

from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.models.parameter_type as db_parameter_type
import lib.db.models.physio_file as db_physio_file
import lib.db.models.project as db_project
from lib.db.base import Base


class DbPhysioFileParameter(Base):
    __tablename__ = 'physiological_parameter_file'

    id          : Mapped[int]        = mapped_column('PhysiologicalParameterFileID', primary_key=True)
    file_id     : Mapped[int | None] = mapped_column('PhysiologicalFileID', ForeignKey('physiological_file.PhysiologicalFileID'))
    project_id  : Mapped[int | None] = mapped_column('ProjectID', ForeignKey('Project.ProjectID'))
    type_id     : Mapped[int]        = mapped_column('ParameterTypeID', ForeignKey('parameter_type.ParameterTypeID'))
    insert_time : Mapped[datetime]   = mapped_column('InsertTime', default=datetime.now)
    value       : Mapped[str | None] = mapped_column('Value')

    file    : Mapped['db_physio_file.DbPhysioFile']       = relationship('DbPhysioFile', back_populates='parameters')
    project : Mapped['db_project.DbProject']              = relationship('DbProject')
    type    : Mapped['db_parameter_type.DbParameterType'] = relationship('DbParameterType')
