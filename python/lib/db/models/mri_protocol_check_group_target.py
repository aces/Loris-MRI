from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.models.cohort as db_cohort
import lib.db.models.mri_protocol_check_group as db_mri_protocol_check_group
import lib.db.models.project as db_project
from lib.db.base import Base


class DbMriProtocolCheckGroupTarget(Base):
    __tablename__ = 'mri_protocol_checks_group_target'

    id                      : Mapped[int]        = mapped_column('MriProtocolChecksGroupTargetID', primary_key=True)
    protocol_check_group_id : Mapped[int]        = mapped_column('MriProtocolChecksGroupID', ForeignKey('mri_protocol_checks_group.MriProtocolChecksGroupID'))
    project_id              : Mapped[int | None] = mapped_column('ProjectID', ForeignKey('Project.ProjectID'))
    cohort_id               : Mapped[int | None] = mapped_column('CohortID', ForeignKey('cohort.CohortID'))
    visit_label             : Mapped[str | None] = mapped_column('Visit_label')

    project              : Mapped['db_project.DbProject | None'] \
        = relationship('DbProject')
    cohort               : Mapped['db_cohort.DbCohort | None'] \
        = relationship('DbCohort')
    protocol_check_group : Mapped['db_mri_protocol_check_group.DbMriProtocolCheckGroup'] \
        = relationship('DbMriProtocolCheckGroup')
