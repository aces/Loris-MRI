from sqlalchemy.orm import Session as Database

from lib.dataclass.config import SubjectConfig
from lib.db.model.candidate import DbCandidate
from lib.db.model.session import DbSession
from lib.db.query.site import try_get_site_with_psc_id_visit_label
from lib.db.query.session import try_get_session_with_cand_id_visit_label


def get_candidate_next_visit_number(candidate: DbCandidate):
    """
    Get the next visit number for a new session for a given candidate.
    """

    visit_numbers = [session.visit_number for session in candidate.sessions if session.visit_number is not None]
    return max(*visit_numbers, 0) + 1


def get_subject_session(db: Database, subject: SubjectConfig) -> DbSession:
    """
    Get the imaging session corresponding to a given subject configuration.

    This function first looks for an adequate session in the database, and returns it if one is
    found. If no session is found, this function creates a new session in the database if the
    subject configuration allows it, or exits the program otherwise.
    """

    session = try_get_session_with_cand_id_visit_label(db, subject.cand_id, subject.visit_label)
    if session is not None:
        # TODO: Log
        # f"Session ID for the file to insert is {self.session_obj.session_info_dict['ID']}"
        # self.log_info(message, is_error="N", is_verbose="Y")
        return session

    if subject.create_visit is None:
        # TODO: Log and exit
        # f"Visit {self.subject.visit_label} for candidate {self.subject.cand_id} does not exist."
        # self.log_error_and_exit(message, lib.exitcode.GET_SESSION_ID_FAILURE, is_error="Y", is_verbose="N")
        return exit(-1)

    if subject.is_phantom:
        site = try_get_site_with_psc_id_visit_label(db, subject.psc_id, subject.visit_label)
        visit_number = 1
    else:
        # TODO: Get real candidate
        candidate = DbCandidate()
        site = candidate.registration_site
        visit_number = get_candidate_next_visit_number(candidate)

    if site is None:
        # message = f"No center ID found for candidate {self.subject.cand_id}, visit {self.subject.visit_label}"
        return exit(-1)

    session = DbSession(
        cand_id       = subject.cand_id,
        site_id       = site.id,
        visit_number  = visit_number,
        current_stage = 'Not Started',
        scan_done     = 'Y',
        submitted     = 'N',
        project_id    = subject.create_visit.project_id,
        cohort_id     = subject.create_visit.cohort_id,
    )

    db.add(session)
    db.flush()

    return session
