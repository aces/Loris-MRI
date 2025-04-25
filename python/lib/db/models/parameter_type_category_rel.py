from sqlalchemy.orm import Mapped, mapped_column

from lib.db.base import Base


class DbParameterTypeCategoryRel(Base):
    __tablename__ = 'parameter_type_category_rel'

    parameter_type_id          : Mapped[int] = mapped_column('ParameterTypeID',         primary_key=True)
    parameter_type_category_id : Mapped[int] = mapped_column('ParameterTypeCategoryID', primary_key=True)
