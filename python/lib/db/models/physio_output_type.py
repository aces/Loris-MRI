from sqlalchemy.orm import Mapped, mapped_column

from lib.db.base import Base


class DbPhysioOutputType(Base):
    __tablename__ = 'physiological_output_type'

    id          : Mapped[int]        = mapped_column('PhysiologicalOutputTypeID', primary_key=True)
    name        : Mapped[str]        = mapped_column('OutputTypeName')
    description : Mapped[str | None] = mapped_column('OutputTypeDescription')
