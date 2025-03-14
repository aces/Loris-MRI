from typing import Never

from sqlalchemy.orm import Session as Database

from lib.config_file import SubjectInfo
from lib.db.queries.candidate import try_get_candidate_with_cand_id
from lib.db.queries.project import try_get_project_cohort_with_project_id_cohort_id
from lib.db.queries.visit import try_get_visit_window_with_visit_label
from lib.exception.validate_subject_info_error import ValidateSubjectInfoError


def validate_subject_info(db: Database, subject_info: SubjectInfo):
    """
    Validate a subject's information against the database from its parts (PSCID, CandID, VisitLabel).
    Raise an exception if an error is found, or return `None` otherwise.
    """

    candidate = try_get_candidate_with_cand_id(db, subject_info.cand_id)
    if candidate is None:
        validate_subject_error(
            subject_info,
            f'Candidate (CandID = \'{subject_info.cand_id}\') does not exist in the database.'
        )

    if candidate.psc_id != subject_info.psc_id:
        validate_subject_error(
            subject_info,
            f'Candidate (CandID = \'{subject_info.cand_id}\') PSCID does not match the subject PSCID.\n'
            f'Candidate PSCID = \'{candidate.psc_id}\', Subject PSCID = \'{subject_info.psc_id}\''
        )

    visit_window = try_get_visit_window_with_visit_label(db, subject_info.visit_label)
    if visit_window is not None:
        return

    if subject_info.create_visit is None:
        validate_subject_error(
            subject_info,
            f'Visit label \'{subject_info.visit_label}\' does not exist in the database (table `Visit_Windows`).'
        )

    project_id = subject_info.create_visit.project_id
    cohort_id  = subject_info.create_visit.cohort_id

    project_cohort = try_get_project_cohort_with_project_id_cohort_id(db, project_id, cohort_id)
    if project_cohort is None:
        validate_subject_error(
            subject_info,
            (
                f'Cannot create a session with project ID {project_id} and cohort ID {cohort_id}.\n'
                f'This project and this cohort are not associated in the database (table `project_cohort_rel`).'
            ),
        )


def validate_subject_error(subject_info: SubjectInfo, message: str) -> Never:
    raise ValidateSubjectInfoError(f'Validation error for subject \'{subject_info.name}\'.\n{message}')
