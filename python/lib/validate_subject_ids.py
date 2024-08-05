from lib.database import Database
from lib.database_lib.candidate_db import CandidateDB
from lib.database_lib.visit_windows import VisitWindows
from lib.exception.validate_subject_exception import ValidateSubjectException


# Utility class

class Subject:
    """
    Wrapper for the properties of a subject.
    """

    psc_id: str
    cand_id: str
    visit_label: str

    def __init__(self, psc_id: str, cand_id: str, visit_label: str):
        self.psc_id = psc_id
        self.cand_id = cand_id
        self.visit_label = visit_label

    def get_name(self):
        return f'{self.psc_id}_{self.cand_id}_{self.visit_label}'


# Main validation functions

def validate_subject_parts(
    db: Database,
    verbose: bool,
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
    validate_subject(db, verbose, subject, create_visit)


def validate_subject(db: Database, verbose: bool, subject: Subject, create_visit: bool):
    candidate_db = CandidateDB(db, verbose)
    candidate_psc_id = candidate_db.get_candidate_psc_id(subject.cand_id)
    if candidate_psc_id is None:
        validate_subject_error(
            subject,
            f'Candidate (CandID = \'{subject.cand_id}\') does not exist in the database.'
        )

    if candidate_psc_id != subject.psc_id:
        validate_subject_error(
            subject,
            f'Candidate (CandID = \'{subject.cand_id}\') PSCID does not match the subject PSCID.\n'
            f'Candidate PSCID = \'{candidate_psc_id}\', Subject PSCID = \'{subject.psc_id}\''
        )

    visit_window_db = VisitWindows(db, verbose)
    visit_window_exists = visit_window_db.check_visit_label_exits(subject.visit_label)
    if not visit_window_exists and not create_visit:
        validate_subject_error(
            subject,
            f'Visit label \'{subject.visit_label}\' does not exist in the database (table `Visit_Windows`).'
        )

    print(f'Validation success for subject \'{subject.get_name()}\'.')


def validate_subject_error(subject: Subject, message: str):
    raise ValidateSubjectException(f'Validation error for subject \'{subject.get_name()}\'.\n{message}')
