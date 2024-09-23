from dataclasses import dataclass
from typing import cast
from sqlalchemy.orm import Session as Database
from lib.db.model.candidate import DbCandidate
from lib.db.query.candidate import try_get_candidate_with_cand_id
from lib.db.query.visit import try_get_visit_window_with_visit_label
from lib.exception.validate_subject_exception import ValidateSubjectException


# Utility class

@dataclass
class Subject:
    """
    Wrapper for the properties of a subject.
    """

    psc_id:      str
    cand_id:     str
    visit_label: str

    def get_name(self):
        return f'{self.psc_id}_{self.cand_id}_{self.visit_label}'


# Main validation functions

def validate_subject_ids(
    db: Database,
    psc_id: str,
    cand_id: str,
    visit_label: str,
    create_visit: bool
):
    """
    Validate a subject's information against the database from its parts (PSCID, CandID, VisitLabel).
    Raise an exception if an error is found, or return `None` otherwise.
    """

    subject = Subject(psc_id, cand_id, visit_label)
    validate_subject(db, subject, create_visit)


def validate_subject(db: Database, subject: Subject, create_visit: bool):
    candidate = try_get_candidate_with_cand_id(db, int(subject.cand_id))
    if candidate is None:
        validate_subject_error(
            subject,
            f'Candidate (CandID = \'{subject.cand_id}\') does not exist in the database.'
        )

    # Safe because the previous check raises an exception if the candidate is `None`.
    candidate = cast(DbCandidate, candidate)

    if candidate.psc_id != subject.psc_id:
        validate_subject_error(
            subject,
            f'Candidate (CandID = \'{subject.cand_id}\') PSCID does not match the subject PSCID.\n'
            f'Candidate PSCID = \'{candidate.psc_id}\', Subject PSCID = \'{subject.psc_id}\''
        )

    visit_window = try_get_visit_window_with_visit_label(db, subject.visit_label)
    if visit_window is None and not create_visit:
        validate_subject_error(
            subject,
            f'Visit label \'{subject.visit_label}\' does not exist in the database (table `Visit_Windows`).'
        )


def validate_subject_error(subject: Subject, message: str):
    raise ValidateSubjectException(f'Validation error for subject \'{subject.get_name()}\'.\n{message}')
