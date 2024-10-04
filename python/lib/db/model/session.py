from datetime import date, datetime
from typing import Optional
from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship
from lib.db.base import Base
import lib.db.model.candidate as db_candidate
import lib.db.model.site as db_site


class DbSession(Base):
    __tablename__ = 'session'

    id                       : Mapped[int]                = mapped_column('ID', primary_key=True)
    cand_id                  : Mapped[int]                = mapped_column('CandID', ForeignKey('candidate.CandID'))
    site_id                  : Mapped[int]                = mapped_column('CenterID', ForeignKey('psc.CenterID'))
    project_id               : Mapped[int]                = mapped_column('ProjectID')
    visit_number             : Mapped[Optional[int]]      = mapped_column('VisitNo')
    visit_label              : Mapped[str]                = mapped_column('Visit_label')
    cohort_id                : Mapped[int]                = mapped_column('CohortID')
    submitted                : Mapped[str]                = mapped_column('Submitted')
    current_stage            : Mapped[str]                = mapped_column('Current_stage')
    date_stage_change        : Mapped[Optional[date]]     = mapped_column('Date_stage_change')
    screening                : Mapped[Optional[str]]      = mapped_column('Screening')
    date_screening           : Mapped[date]               = mapped_column('Date_screening')
    visit                    : Mapped[Optional[str]]      = mapped_column('Visit')
    date_visit               : Mapped[Optional[date]]     = mapped_column('Date_visit')
    date_status_change       : Mapped[Optional[date]]     = mapped_column('Date_status_change')
    approval                 : Mapped[Optional[str]]      = mapped_column('Approval')
    date_approval            : Mapped[Optional[date]]     = mapped_column('Date_approval')
    active                   : Mapped[str]                = mapped_column('Active')
    date_active              : Mapped[Optional[date]]     = mapped_column('Date_active')
    registered_by            : Mapped[Optional[str]]      = mapped_column('RegisteredBy')
    user_id                  : Mapped[str]                = mapped_column('UserID')
    date_registered          : Mapped[Optional[date]]     = mapped_column('Date_registered')
    test_date                : Mapped[int]                = mapped_column('Testdate')
    hardcopy_request         : Mapped[str]                = mapped_column('Hardcopy_request')
    bvl_qc_status            : Mapped[Optional[str]]      = mapped_column('BVLQCStaus')
    bvl_qc_type              : Mapped[Optional[str]]      = mapped_column('BVLQCType')
    bvl_qc_exclusion         : Mapped[Optional[str]]      = mapped_column('BVLQCExclusion')
    qcd                      : Mapped[Optional[str]]      = mapped_column('QCd')
    scan_done                : Mapped[Optional[str]]      = mapped_column('Scan_done')
    mri_qc_status            : Mapped[str]                = mapped_column('MRIQCStatus')
    mri_qc_pending           : Mapped[str]                = mapped_column('MRIQCPending')
    mri_qc_first_change_time : Mapped[Optional[datetime]] = mapped_column('MRIQCFirstChange')
    mri_qc_last_change_time  : Mapped[Optional[datetime]] = mapped_column('MRIQCLastChange')
    mri_caveat               : Mapped[str]                = mapped_column('MRICaveat')
    language_id              : Mapped[Optional[int]]      = mapped_column('languageID')

    candidate : Mapped['db_candidate.DbCandidate'] = relationship('DbCandidate', back_populates='sessions')
    site      : Mapped['db_site.DbSite']           = relationship('DbSite')
