from sqlalchemy.orm import Mapped, mapped_column

from lib.db.base import Base


class DbPhysioModality(Base):
    __tablename__ = 'physiological_modality'

    id   : Mapped[int] = mapped_column('PhysiologicalModalityID', primary_key=True)
    name : Mapped[str] = mapped_column('PhysiologicalModality')
