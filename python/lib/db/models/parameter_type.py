from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.models.parameter_file as db_parameter_file
from lib.db.base import Base


class DbParameterType(Base):
    __tablename__ = 'parameter_type'

    id               : Mapped[int]          = mapped_column('ParameterTypeID', primary_key=True)
    name             : Mapped[str]          = mapped_column('Name')
    alias            : Mapped[str | None]   = mapped_column('Alias')
    data_type        : Mapped[str | None]   = mapped_column('Type')
    description      : Mapped[str | None]   = mapped_column('Description')
    range_min        : Mapped[float | None] = mapped_column('RangeMin')
    range_max        : Mapped[float | None] = mapped_column('RangeMax')
    source_field     : Mapped[str | None]   = mapped_column('SourceField')
    source_from      : Mapped[str | None]   = mapped_column('SourceFrom')
    source_condition : Mapped[str | None]   = mapped_column('SourceCondition')
    queryable        : Mapped[bool | None]  = mapped_column('Queryable')
    isfile           : Mapped[bool | None]  = mapped_column('IsFile')

    parameter_file: Mapped['db_parameter_file.DbParameterFile'] \
        = relationship('DbParameterFile', back_populates='parameter_type')
