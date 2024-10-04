from datetime import date
from typing import Optional

from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.model.project as db_project
import lib.db.model.session as db_session
import lib.db.model.site as db_site
from lib.db.base import Base
from lib.db.decorator.y_n_bool import YNBool


class DbCandidate(Base):
    __tablename__ = 'candidate'

    id                      : Mapped[int]            = mapped_column('ID', primary_key=True)
    cand_id                 : Mapped[int]            = mapped_column('CandID')
    psc_id                  : Mapped[str]            = mapped_column('PSCID')
    external_id             : Mapped[Optional[str]]  = mapped_column('ExternalID')
    date_of_birth           : Mapped[Optional[date]] = mapped_column('DoB')
    dete_of_death           : Mapped[Optional[date]] = mapped_column('DoD')
    edc                     : Mapped[Optional[date]] = mapped_column('EDC')
    sex                     : Mapped[Optional[str]]  = mapped_column('Sex')
    registration_site_id    : Mapped[int]            = mapped_column('RegistrationCenterID', ForeignKey('psc.CenterID'))
    registration_project_id : Mapped[int] \
        = mapped_column('RegistrationProjectID', ForeignKey('Project.ProjectID'))
    ethnicity               : Mapped[Optional[str]]  = mapped_column('Ethnicity')
    active                  : Mapped[bool]           = mapped_column('Active', YNBool)
    date_active             : Mapped[Optional[date]] = mapped_column('Date_active')
    registered_by           : Mapped[Optional[str]]  = mapped_column('RegisteredBy')
    user_id                 : Mapped[str]            = mapped_column('UserID')
    date_registered         : Mapped[Optional[date]] = mapped_column('Date_registered')
    flagged_caveatemptor    : Mapped[Optional[str]]  = mapped_column('flagged_caveatemptor')
    flagged_reason          : Mapped[Optional[int]]  = mapped_column('flagged_reason')
    flagged_other           : Mapped[Optional[str]]  = mapped_column('flagged_other')
    flagged_other_status    : Mapped[Optional[str]]  = mapped_column('flagged_other_status')
    test_date               : Mapped[int]            = mapped_column('Testdate')
    entity_type             : Mapped[str]            = mapped_column('Entity_type')
    proband_sex             : Mapped[Optional[str]]  = mapped_column('ProbandSex')
    proband_sate_of_birth   : Mapped[Optional[date]] = mapped_column('ProbandDoB')

    sessions             : Mapped[list['db_session.DbSession']] \
        = relationship('DbSession', back_populates='candidate')
    registration_site    : Mapped['db_site.DbSite'] \
        = relationship('DbSite')
    registration_project : Mapped['db_project.DbProject'] \
        = relationship('DbProject')
