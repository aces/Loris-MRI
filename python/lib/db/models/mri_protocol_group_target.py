from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.models.cohort as db_cohort
import lib.db.models.mri_protocol_group as db_mri_protocol_group
import lib.db.models.project as db_project
from lib.db.base import Base


class DbMriProtocolGroupTarget(Base):
    __tablename__ = 'mri_protocol_group_target'

    id                : Mapped[int]        = mapped_column('MriProtocolGroupTargetID', primary_key=True)
    protocol_group_id : Mapped[int]        = mapped_column('MriProtocolGroupID', ForeignKey('mri_protocol_group.MriProtocolGroupID'))
    project_id        : Mapped[int | None] = mapped_column('ProjectID', ForeignKey('Project.ProjectID'))
    cohort_id         : Mapped[int | None] = mapped_column('CohortID', ForeignKey('cohort.CohortID'))
    visit_label       : Mapped[str | None] = mapped_column('Visit_label')

    project        : Mapped['db_project.DbProject | None'] \
        = relationship('DbProject')
    cohort         : Mapped['db_cohort.DbCohort | None'] \
        = relationship('DbCohort')
    protocol_group : Mapped['db_mri_protocol_group.DbMriProtocolGroup'] \
        = relationship('DbMriProtocolGroup')
