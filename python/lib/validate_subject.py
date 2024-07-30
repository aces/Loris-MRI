from lib.database import Database
from lib.database_lib.candidate_db import CandidateDB
from lib.database_lib.visit_windows import VisitWindows
from lib.log import Log

# Utility classes

class Env:
    """
    Wrapper class for global objects used during the validation.
    """

    db: Database
    logger: Log
    verbose: bool


    def __init__(self, db: Database, logger: Log, verbose: bool):
        self.db      = db
        self.logger  = logger
        self.verbose = verbose


    def log_info(self, message: str, is_error: bool, is_verbose: bool):
        """
        Log information in the notification_spool table and in the log  file produced by the script
        being executed.

        :param message: Message to log.
        :param is_error: Whether the message is an error or not.
        :param is_verbose: Whether the message is considered verbose or not in the \
            `notification_spool` table. \
        """
        if self.logger:
            log_msg = f'==> {message}'
            self.logger.write_to_log_file(f'{log_msg}\n')
            self.logger.write_to_notification_table(
                log_msg,
                'Y' if is_error else 'N',
                'Y' if is_verbose else 'N'
            )

            if self.verbose:
                print(f'{log_msg}\n')


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

def validate_subject_name(
    db: Database,
    logger: Log,
    verbose: bool,
    subject_name: str,
    create_visit: bool
):
    """
    Validate a subject's information against the database from its name.
    Return `None` if no error is found, or a string describing the error otherwise.
    """

    env = Env(db, logger, verbose)
    subject_parts = subject_name.split('_')
    match subject_parts:
        case [psc_id, cand_id, visit_label]:
            subject = Subject(psc_id, cand_id, visit_label)
            return validate_subject(env, subject, create_visit)
        case _:
            return validation_error_name(
                env,
                subject_name,
                'Expected subject name to be of format \'PSCID_CandID_VisitLabel\'.'
            )


def validate_subject_parts(
    db: Database,
    logger: Log,
    verbose: bool,
    psc_id: str,
    cand_id: str,
    visit_label: str,
    create_visit: bool
):
    """
    Validate a subject's information against the database from its parts (PSCID, CandID, VisitLabel).
    Return `None` if no error is found, or a string describing the error otherwise.
    """

    env = Env(db, logger, verbose)
    subject = Subject(psc_id, cand_id, visit_label)
    return validate_subject(env, subject, create_visit)


def validate_subject(env: Env, subject: Subject, create_visit: bool):
    candidate_db = CandidateDB(env.db, env.verbose)
    candidate_psc_id = candidate_db.get_candidate_psc_id(subject.cand_id)
    if candidate_psc_id is None:
        return validation_error_subject(
            env,
            subject,
            f'Candidate (CandID=\'{subject.cand_id}\') does not exist in the database.'
        )

    if candidate_psc_id != subject.psc_id:
        return validation_error_subject(
            env,
            subject,
            f'Candidate PSCID (CandID=\'{subject.cand_id}\') does not match the subject PSCID.'
        )

    visit_window_db = VisitWindows(env.db, env.verbose)
    visit_window_exists = visit_window_db.check_visit_label_exits(subject.visit_label)
    if not visit_window_exists and not create_visit:
        return validation_error_subject(
            env,
            subject,
            f'Visit label \'{subject.visit_label}\' does not exist in the databse (table: `Visit_Windows`).'
        )

    return validation_success(env, subject)


# Utility success and error logger functions

def validation_success(env: Env, subject: Subject):
    message = f'Validation success for subject \'{subject.get_name()}\'.'
    env.log_info(message, is_error=False, is_verbose=True)
    return None


def validation_error_name(env: Env, subject_name: str, message: str):
    message = f'Validation error for subject \'{subject_name}\'.\n{message}'
    env.log_info(message, is_error=True, is_verbose=True)
    return message


def validation_error_subject(env: Env, subject: Subject, message: str):
    return validation_error_name(env, subject.get_name(), message)
