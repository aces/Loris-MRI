from datetime import date, datetime

from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.models.mri_protocol_violated_scan as db_mri_protocol_violated_scan
import lib.db.models.mri_violation_log as db_mri_violation_log
import lib.db.models.project as db_project
import lib.db.models.session as db_session
import lib.db.models.site as db_site
from lib.db.base import Base
from lib.db.decorators.y_n_bool import YNBool


class DbCandidate(Base):
    __tablename__ = 'candidate'

    id                      : Mapped[int]         = mapped_column('ID', primary_key=True)
    cand_id                 : Mapped[int]         = mapped_column('CandID')
    psc_id                  : Mapped[str]         = mapped_column('PSCID')
    external_id             : Mapped[str | None]  = mapped_column('ExternalID')
    date_of_birth           : Mapped[date | None] = mapped_column('DoB')
    dete_of_death           : Mapped[date | None] = mapped_column('DoD')
    edc                     : Mapped[date | None] = mapped_column('EDC')
    sex                     : Mapped[str | None]  = mapped_column('Sex')
    registration_site_id    : Mapped[int]         = mapped_column('RegistrationCenterID', ForeignKey('psc.CenterID'))
    registration_project_id : Mapped[int] \
        = mapped_column('RegistrationProjectID', ForeignKey('Project.ProjectID'))
    ethnicity               : Mapped[str | None]  = mapped_column('Ethnicity')
    active                  : Mapped[bool]        = mapped_column('Active', YNBool)
    date_active             : Mapped[date | None] = mapped_column('Date_active')
    registered_by           : Mapped[str | None]  = mapped_column('RegisteredBy')
    user_id                 : Mapped[str]         = mapped_column('UserID')
    date_registered         : Mapped[date | None] = mapped_column('Date_registered')
    flagged_caveatemptor    : Mapped[str | None]  = mapped_column('flagged_caveatemptor')
    flagged_reason          : Mapped[int | None]  = mapped_column('flagged_reason')
    flagged_other           : Mapped[str | None]  = mapped_column('flagged_other')
    flagged_other_status    : Mapped[str | None]  = mapped_column('flagged_other_status')
    test_date               : Mapped[datetime]    = mapped_column('Testdate')
    entity_type             : Mapped[str]         = mapped_column('Entity_type')
    proband_sex             : Mapped[str | None]  = mapped_column('ProbandSex')
    proband_sate_of_birth   : Mapped[date | None] = mapped_column('ProbandDoB')

    sessions             : Mapped[list['db_session.DbSession']] \
        = relationship('DbSession', back_populates='candidate')
    registration_site    : Mapped['db_site.DbSite'] \
        = relationship('DbSite')
    registration_project : Mapped['db_project.DbProject'] \
        = relationship('DbProject')
    violated_scans       : Mapped[list['db_mri_protocol_violated_scan.DbMriProtocolViolatedScan']] \
        = relationship('DbMriProtocolViolatedScan', back_populates='candidate')
    violations_log       : Mapped[list['db_mri_violation_log.DbMriViolationLog']] \
        = relationship('DbMriViolationLog', back_populates='candidate')
