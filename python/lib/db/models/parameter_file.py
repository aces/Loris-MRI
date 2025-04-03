from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.models.file as db_file
import lib.db.models.parameter_type as db_parameter_type
from lib.db.base import Base


class DbParameterFile(Base):
    __tablename__ = 'parameter_file'

    id                : Mapped[int]        = mapped_column('ParameterFileID', primary_key=True)
    file_id           : Mapped[int]        = mapped_column('FileID', ForeignKey('files.FileID'))
    parameter_type_id : Mapped[int]        \
        = mapped_column('ParameterTypeID', ForeignKey('parameter_type.ParameterTypeID'))
    value             : Mapped[str | None] = mapped_column('Value')
    insert_time       : Mapped[int]        = mapped_column('InsertTime')

    file          : Mapped['db_file.DbFile'] = relationship('DbFile', back_populates='parameter_file')
    parameter_type: Mapped['db_parameter_type.DbParameterType'] \
        = relationship('DbParameterType', back_populates='parameter_file')
