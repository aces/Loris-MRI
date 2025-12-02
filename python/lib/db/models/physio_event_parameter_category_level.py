from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.models.physio_event_parameter as db_physio_event_parameter
from lib.db.base import Base


class DbPhysioEventParameterCategoryLevel(Base):
    __tablename__ = 'physiological_event_parameter_category_level'

    id                 : Mapped[int]        = mapped_column('CategoricalLevelID', primary_key=True)
    event_parameter_id : Mapped[int]        = mapped_column('EventParameterID', ForeignKey('physiological_event_parameter.EventParameterID'))
    level_name         : Mapped[str]        = mapped_column('LevelName')
    description        : Mapped[str | None] = mapped_column('Description')
    hed                : Mapped[str | None] = mapped_column('HED')

    event_parameter: Mapped['db_physio_event_parameter.DbPhysioEventParameter'] = relationship('PhysiologicalEventParameter', back_populates='category_levels')
