from datetime import date, datetime
from typing import Optional

from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.sql.functions import current_timestamp

import lib.db.model.candidate as db_candidate
import lib.db.model.project as db_project
import lib.db.model.site as db_site
from lib.db.base import Base
from lib.db.decorator.true_false_bool import TrueFalseBool
from lib.db.decorator.y_n_bool import YNBool


class DbSession(Base):
    __tablename__ = 'session'

    id                       : Mapped[int]                = mapped_column('ID',
        primary_key=True, autoincrement=True, init=False)
    cand_id                  : Mapped[int]                = mapped_column('CandID', ForeignKey('candidate.CandID'))
    site_id                  : Mapped[int]                = mapped_column('CenterID', ForeignKey('psc.CenterID'))
    project_id               : Mapped[int]                = mapped_column('ProjectID', ForeignKey('Project.ProjectID'))
    visit_label              : Mapped[str]                = mapped_column('Visit_label')
    visit_number             : Mapped[Optional[int]]      = mapped_column('VisitNo',              default=None)
    cohort_id                : Mapped[Optional[int]]      = mapped_column('CohortID',             default=None)
    submitted                : Mapped[bool]               = mapped_column('Submitted', YNBool,    default=False)
    current_stage            : Mapped[str]                = mapped_column('Current_stage',        default='Not Started')
    date_stage_change        : Mapped[Optional[date]]     = mapped_column('Date_stage_change',    default=None)
    screening                : Mapped[Optional[str]]      = mapped_column('Screening',            default=None)
    date_screening           : Mapped[Optional[date]]     = mapped_column('Date_screening',       default=None)
    visit                    : Mapped[Optional[str]]      = mapped_column('Visit',                default=None)
    date_visit               : Mapped[Optional[date]]     = mapped_column('Date_visit',           default=None)
    date_status_change       : Mapped[Optional[date]]     = mapped_column('Date_status_change',   default=None)
    approval                 : Mapped[Optional[str]]      = mapped_column('Approval',             default=None)
    date_approval            : Mapped[Optional[date]]     = mapped_column('Date_approval',        default=None)
    active                   : Mapped[bool]               = mapped_column('Active', YNBool,       default=True)
    date_active              : Mapped[Optional[date]]     = mapped_column('Date_active',          default=None)
    registered_by            : Mapped[Optional[str]]      = mapped_column('RegisteredBy',         default=None)
    user_id                  : Mapped[str]                = mapped_column('UserID',               default='')
    date_registered          : Mapped[Optional[date]]     = mapped_column('Date_registered',      default=None)
    test_date                : Mapped[datetime]           = mapped_column('Testdate',
        default=current_timestamp(), onupdate=current_timestamp())
    hardcopy_request         : Mapped[str]                = mapped_column('Hardcopy_request',     default='-')
    bvl_qc_status            : Mapped[Optional[str]]      = mapped_column('BVLQCStatus',          default=None)
    bvl_qc_type              : Mapped[Optional[str]]      = mapped_column('BVLQCType',            default=None)
    bvl_qc_exclusion         : Mapped[Optional[str]]      = mapped_column('BVLQCExclusion',       default=None)
    qcd                      : Mapped[Optional[str]]      = mapped_column('QCd',                  default=None)
    scan_done                : Mapped[Optional[bool]]     = mapped_column('Scan_done', YNBool,    default=None)
    mri_qc_status            : Mapped[str]                = mapped_column('MRIQCStatus',          default='')
    mri_qc_pending           : Mapped[bool]               = mapped_column('MRIQCPending', YNBool, default=False)
    mri_qc_first_change_time : Mapped[Optional[datetime]] = mapped_column('MRIQCFirstChangeTime', default=None)
    mri_qc_last_change_time  : Mapped[Optional[datetime]] = mapped_column('MRIQCLastChangeTime',  default=None)
    mri_caveat               : Mapped[str]                = mapped_column('MRICaveat',
        TrueFalseBool, default=False)
    language_id              : Mapped[Optional[int]]      = mapped_column('languageID',           default=None)

    candidate : Mapped['db_candidate.DbCandidate'] = relationship('DbCandidate', back_populates='sessions', init=False)
    project   : Mapped['db_project.DbProject']     = relationship('DbProject', init=False)
    site      : Mapped['db_site.DbSite']           = relationship('DbSite', init=False)
