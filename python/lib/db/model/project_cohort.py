from sqlalchemy.orm import Mapped, mapped_column

from lib.db.base import Base


class DbProjectCohort(Base):
    __tablename__ = 'project_cohort_rel'

    id         : Mapped[int] = mapped_column('ProjectCohortRelID', primary_key=True)
    project_id : Mapped[int] = mapped_column('ProjectID')
    cohort_id  : Mapped[int] = mapped_column('CohortID')
