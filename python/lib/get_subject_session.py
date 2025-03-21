from typing import cast

import lib.exitcode
from lib.config_file import SubjectInfo
from lib.db.models.candidate import DbCandidate
from lib.db.models.session import DbSession
from lib.db.queries.candidate import try_get_candidate_with_cand_id
from lib.db.queries.session import try_get_session_with_cand_id_visit_label
from lib.db.queries.site import try_get_site_with_cand_id_visit_label
from lib.env import Env
from lib.logging import log_error_exit, log_verbose


def get_candidate_next_visit_number(candidate: DbCandidate) -> int:
    """
    Get the next visit number for a new session for a given candidate.
    """

    visit_numbers = [session.visit_number for session in candidate.sessions if session.visit_number is not None]
    return max(*visit_numbers, 0) + 1


def get_subject_session(env: Env, subject_info: SubjectInfo) -> DbSession:
    """
    Get the imaging session corresponding to a given subject configuration.

    This function first looks for an adequate session in the database, and returns it if one is
    found. If no session is found, this function creates a new session in the database if the
    subject configuration allows it, or exits the program otherwise.
    """

    session = _get_subject_session(env, subject_info)
    log_verbose(env, f"Session ID for the file to insert is {session.id}")
    return session


def _get_subject_session(env: Env, subject_info: SubjectInfo) -> DbSession:
    """
    Implementation of `get_subject_session`.
    """

    session = try_get_session_with_cand_id_visit_label(env.db, subject_info.cand_id, subject_info.visit_label)
    if session is not None:
        return session

    if subject_info.create_visit is None:
        log_error_exit(
            env,
            f"Visit {subject_info.visit_label} for candidate {subject_info.cand_id} does not exist.",
            lib.exitcode.GET_SESSION_ID_FAILURE,
        )

    if subject_info.is_phantom:
        site = try_get_site_with_cand_id_visit_label(env.db, subject_info.cand_id, subject_info.visit_label)
        visit_number = 1
    else:
        candidate = try_get_candidate_with_cand_id(env.db, subject_info.cand_id)
        # Safe because it has been checked that the candidate exists in `validate_subject_info`
        candidate = cast(DbCandidate, candidate)
        site = candidate.registration_site
        visit_number = get_candidate_next_visit_number(candidate)

    if site is None:
        log_error_exit(
            env,
            f"No center ID found for candidate {subject_info.cand_id}, visit {subject_info.visit_label}"
        )

    log_verbose(env, f"Set newVisitNo = {visit_number} and center ID = {site.id}")

    session = DbSession(
        cand_id       = subject_info.cand_id,
        site_id       = site.id,
        visit_number  = visit_number,
        current_stage = 'Not Started',
        scan_done     = True,
        submitted     = False,
        project_id    = subject_info.create_visit.project_id,
        cohort_id     = subject_info.create_visit.cohort_id,
    )

    env.db.add(session)
    env.db.commit()

    return session
