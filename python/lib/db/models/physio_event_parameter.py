from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.models.physio_event_file as db_physio_event_file
import lib.db.models.physio_event_parameter_category_level as db_physio_event_parameter_category_level
from lib.db.base import Base
from lib.db.decorators.y_n_bool import YNBool


class DbPhysioEventParameter(Base):
    __tablename__ = 'physiological_event_parameter'

    id             : Mapped[int]         = mapped_column('EventParameterID', primary_key=True)
    event_file_id  : Mapped[int]         = mapped_column('EventFileID', ForeignKey('physiological_event_file.EventFileID'))
    parameter_name : Mapped[str]         = mapped_column('ParameterName')
    description    : Mapped[str | None]  = mapped_column('Description')
    long_name      : Mapped[str | None]  = mapped_column('LongName')
    units          : Mapped[str | None]  = mapped_column('Units')
    is_categorical : Mapped[bool | None] = mapped_column('isCategorical', YNBool)
    hed            : Mapped[str | None]  = mapped_column('HED')

    event_file      : Mapped['db_physio_event_file.DbPhysioEventFile']                                             = relationship('DbPhysioEventFile')
    category_levels : Mapped[list['db_physio_event_parameter_category_level.DbPhysioEventParameterCategoryLevel']] = relationship('DbPhysioEventParameterCategoryLevel', back_populates='event_parameter')
