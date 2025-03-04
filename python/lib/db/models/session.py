from datetime import date, datetime

from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.models.candidate as db_candidate
import lib.db.models.file as db_file
import lib.db.models.project as db_project
import lib.db.models.site as db_site
from lib.db.base import Base
from lib.db.decorators.y_n_bool import YNBool


class DbSession(Base):
    __tablename__ = 'session'

    id                       : Mapped[int]             = mapped_column('ID', primary_key=True)
    candidate_id             : Mapped[int]             = mapped_column('CandidateID', ForeignKey('candidate.ID'))
    site_id                  : Mapped[int]             = mapped_column('CenterID', ForeignKey('psc.CenterID'))
    project_id               : Mapped[int]             = mapped_column('ProjectID', ForeignKey('Project.ProjectID'))
    visit_number             : Mapped[int | None]      = mapped_column('VisitNo')
    visit_label              : Mapped[str]             = mapped_column('Visit_label')
    cohort_id                : Mapped[int | None]      = mapped_column('CohortID')
    submitted                : Mapped[bool]            = mapped_column('Submitted', YNBool)
    current_stage            : Mapped[str]             = mapped_column('Current_stage')
    date_stage_change        : Mapped[date | None]     = mapped_column('Date_stage_change')
    screening                : Mapped[str | None]      = mapped_column('Screening')
    date_screening           : Mapped[date | None]     = mapped_column('Date_screening')
    visit                    : Mapped[str | None]      = mapped_column('Visit')
    date_visit               : Mapped[date | None]     = mapped_column('Date_visit')
    date_status_change       : Mapped[date | None]     = mapped_column('Date_status_change')
    approval                 : Mapped[str | None]      = mapped_column('Approval')
    date_approval            : Mapped[date | None]     = mapped_column('Date_approval')
    active                   : Mapped[bool]            = mapped_column('Active', YNBool)
    date_active              : Mapped[date | None]     = mapped_column('Date_active')
    registered_by            : Mapped[str | None]      = mapped_column('RegisteredBy')
    user_id                  : Mapped[str]             = mapped_column('UserID')
    date_registered          : Mapped[date | None]     = mapped_column('Date_registered')
    test_date                : Mapped[datetime]        = mapped_column('Testdate')
    hardcopy_request         : Mapped[str]             = mapped_column('Hardcopy_request')
    bvl_qc_status            : Mapped[str | None]      = mapped_column('BVLQCStatus')
    bvl_qc_type              : Mapped[str | None]      = mapped_column('BVLQCType')
    bvl_qc_exclusion         : Mapped[str | None]      = mapped_column('BVLQCExclusion')
    qcd                      : Mapped[str | None]      = mapped_column('QCd')
    scan_done                : Mapped[bool | None]     = mapped_column('Scan_done', YNBool)
    mri_qc_status            : Mapped[str]             = mapped_column('MRIQCStatus')
    mri_qc_pending           : Mapped[bool]            = mapped_column('MRIQCPending', YNBool)
    mri_qc_first_change_time : Mapped[datetime | None] = mapped_column('MRIQCFirstChangeTime')
    mri_qc_last_change_time  : Mapped[datetime | None] = mapped_column('MRIQCLastChangeTime')
    mri_caveat               : Mapped[str]             = mapped_column('MRICaveat')
    language_id              : Mapped[int | None]      = mapped_column('languageID')

    candidate : Mapped['db_candidate.DbCandidate'] = relationship('DbCandidate', back_populates='sessions')
    files     : Mapped[list['db_file.DbFile']]     = relationship('DbFile', back_populates='session')
    project   : Mapped['db_project.DbProject']     = relationship('DbProject')
    site      : Mapped['db_site.DbSite']           = relationship('DbSite')
