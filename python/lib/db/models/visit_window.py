from sqlalchemy.orm import Mapped, mapped_column

from lib.db.base import Base


class DbVisitWindow(Base):
    __tablename__  = 'Visit_Windows'

    id                   : Mapped[int]        = mapped_column('ID', primary_key=True)
    visit_label          : Mapped[str | None] = mapped_column('Visit_label')
    window_min_days      : Mapped[int | None] = mapped_column('WindowMinDays')
    window_max_days      : Mapped[int | None] = mapped_column('WindowMaxDays')
    optimum_min_days     : Mapped[int | None] = mapped_column('OptimumMinDays')
    optimum_max_days     : Mapped[int | None] = mapped_column('OptimumMaxDays')
    window_midpoint_days : Mapped[int | None] = mapped_column('WindowMidpointDays')
