from datetime import date, datetime
from typing import Optional

from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.model.candidate as db_candidate
import lib.db.model.project as db_project
import lib.db.model.site as db_site
from lib.db.base import Base
from lib.db.decorator.y_n_bool import YNBool


class DbSession(Base):
    __tablename__ = 'session'

    id                       : Mapped[int]                = mapped_column('ID', primary_key=True)
    cand_id                  : Mapped[int]                = mapped_column('CandID', ForeignKey('candidate.CandID'))
    site_id                  : Mapped[int]                = mapped_column('CenterID', ForeignKey('psc.CenterID'))
    project_id               : Mapped[int]                = mapped_column('ProjectID', ForeignKey('Project.ProjectID'))
    visit_number             : Mapped[Optional[int]]      = mapped_column('VisitNo')
    visit_label              : Mapped[str]                = mapped_column('Visit_label')
    cohort_id                : Mapped[Optional[int]]      = mapped_column('CohortID')
    submitted                : Mapped[bool]               = mapped_column('Submitted', YNBool)
    current_stage            : Mapped[str]                = mapped_column('Current_stage')
    date_stage_change        : Mapped[Optional[date]]     = mapped_column('Date_stage_change')
    screening                : Mapped[Optional[str]]      = mapped_column('Screening')
    date_screening           : Mapped[Optional[date]]     = mapped_column('Date_screening')
    visit                    : Mapped[Optional[str]]      = mapped_column('Visit')
    date_visit               : Mapped[Optional[date]]     = mapped_column('Date_visit')
    date_status_change       : Mapped[Optional[date]]     = mapped_column('Date_status_change')
    approval                 : Mapped[Optional[str]]      = mapped_column('Approval')
    date_approval            : Mapped[Optional[date]]     = mapped_column('Date_approval')
    active                   : Mapped[bool]               = mapped_column('Active', YNBool)
    date_active              : Mapped[Optional[date]]     = mapped_column('Date_active')
    registered_by            : Mapped[Optional[str]]      = mapped_column('RegisteredBy')
    user_id                  : Mapped[str]                = mapped_column('UserID')
    date_registered          : Mapped[Optional[date]]     = mapped_column('Date_registered')
    test_date                : Mapped[datetime]           = mapped_column('Testdate')
    hardcopy_request         : Mapped[str]                = mapped_column('Hardcopy_request')
    bvl_qc_status            : Mapped[Optional[str]]      = mapped_column('BVLQCStatus')
    bvl_qc_type              : Mapped[Optional[str]]      = mapped_column('BVLQCType')
    bvl_qc_exclusion         : Mapped[Optional[str]]      = mapped_column('BVLQCExclusion')
    qcd                      : Mapped[Optional[str]]      = mapped_column('QCd')
    scan_done                : Mapped[Optional[bool]]     = mapped_column('Scan_done', YNBool)
    mri_qc_status            : Mapped[str]                = mapped_column('MRIQCStatus')
    mri_qc_pending           : Mapped[bool]               = mapped_column('MRIQCPending', YNBool)
    mri_qc_first_change_time : Mapped[Optional[datetime]] = mapped_column('MRIQCFirstChangeTime')
    mri_qc_last_change_time  : Mapped[Optional[datetime]] = mapped_column('MRIQCLastChangeTime')
    mri_caveat               : Mapped[str]                = mapped_column('MRICaveat')
    language_id              : Mapped[Optional[int]]      = mapped_column('languageID')

    candidate : Mapped['db_candidate.DbCandidate'] = relationship('DbCandidate', back_populates='sessions')
    project   : Mapped['db_project.DbProject']     = relationship('DbProject')
    site      : Mapped['db_site.DbSite']           = relationship('DbSite')
