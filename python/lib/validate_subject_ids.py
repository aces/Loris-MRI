from typing import Never
from sqlalchemy.orm import Session as Database
from lib.dataclass.config import SubjectConfig
from lib.db.query.candidate import try_get_candidate_with_cand_id
from lib.db.query.visit import try_get_visit_window_with_visit_label
from lib.exception.validate_subject_info_error import ValidateSubjectInfoError


def validate_subject_ids(db: Database, subject: SubjectConfig):
    """
    Validate a subject's information against the database from its parts (PSCID, CandID, VisitLabel).
    Raise an exception if an error is found, or return `None` otherwise.
    """

    candidate = try_get_candidate_with_cand_id(db, subject.cand_id)
    if candidate is None:
        validate_subject_error(
            subject,
            f'Candidate (CandID = \'{subject.cand_id}\') does not exist in the database.'
        )

    if candidate.psc_id != subject.psc_id:
        validate_subject_error(
            subject,
            f'Candidate (CandID = \'{subject.cand_id}\') PSCID does not match the subject PSCID.\n'
            f'Candidate PSCID = \'{candidate.psc_id}\', Subject PSCID = \'{subject.psc_id}\''
        )

    visit_window = try_get_visit_window_with_visit_label(db, subject.visit_label)
    if visit_window is None and subject.create_visit is not None:
        validate_subject_error(
            subject,
            f'Visit label \'{subject.visit_label}\' does not exist in the database (table `Visit_Windows`).'
        )


def validate_subject_error(subject: SubjectConfig, message: str) -> Never:
    raise ValidateSubjectInfoError(f'Validation error for subject \'{subject.name}\'.\n{message}')
