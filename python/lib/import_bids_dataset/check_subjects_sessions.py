import random
from datetime import datetime

from dateutil.parser import ParserError, parse
from sqlalchemy.orm import Session as Database

from lib.config import get_default_bids_visit_label_config
from lib.db.models.candidate import DbCandidate
from lib.db.models.cohort import DbCohort
from lib.db.models.project import DbProject
from lib.db.models.session import DbSession
from lib.db.models.site import DbSite
from lib.db.queries.candidate import try_get_candidate_with_cand_id, try_get_candidate_with_psc_id
from lib.db.queries.cohort import try_get_cohort_with_name
from lib.db.queries.project import try_get_project_with_alias, try_get_project_with_name
from lib.db.queries.session import try_get_session_with_cand_id_visit_label
from lib.db.queries.sex import try_get_sex_with_name
from lib.db.queries.site import try_get_site_with_alias, try_get_site_with_name
from lib.db.queries.visit import try_get_visit_with_visit_label
from lib.env import Env
from lib.imaging_lib.bids.dataset import BidsDataset, BidsSubject
from lib.imaging_lib.bids.tsv_participants import BidsTsvParticipant
from lib.logging import log, log_error, log_error_exit


class CheckBidsSubjectSessionError(Exception):
    """
    Exception raised if the check or creation of a candidate or session from a BIDS dataset fails.
    """

    def __init__(self, message: str):
        super().__init__(message)


def check_bids_session_labels(
    env: Env,
    bids: BidsDataset,
):
    """
    Check that all the session labels in a BIDS dataset correspond to a LORIS visit, or exit the
    program with an error if that is not the case.
    """

    unknown_session_labels: list[str] = []

    for session_label in bids.session_labels:
        visit = try_get_visit_with_visit_label(env.db, session_label)
        if visit is None:
            unknown_session_labels.append(session_label)

    if unknown_session_labels != []:
        log_error_exit(
            env,
            (
                f"Found {len(unknown_session_labels)} unknown session labels in the BIDS dataset. Unknown session"
                f" labels are: {', '.join(unknown_session_labels)}. Each BIDS session label should correspond to a"
                " LORIS visit label."
            )
        )


def check_or_create_bids_subjects_and_sessions(
    env: Env,
    bids: BidsDataset,
    create_candidate: bool,
    create_session: bool,
) -> int:
    """
    Check that the subjects and sessions of a BIDS dataset correspond to LORIS candidates and
    sessions, or create them using information extracted from the BIDS dataset if the relevant
    arguments are passed.

    Exit the program with an error if the check or creation of any candidate or session fails.
    Return the project ID of the last candidate processed.
    """

    try:
        # Read the participants.tsv property to raise an exception if the file is incorrect.
        bids.tsv_participants
    except Exception as exception:
        log_error_exit(env, f"Error while reading the participants.tsv file. Full error:\n{exception}")

    candidate = None
    errors: list[Exception] = []

    for subject in bids.subjects:
        try:
            candidate = check_or_create_bids_subject_and_sessions(env, subject, create_candidate, create_session)
        except Exception as error:
            log_error(env, str(error))
            errors.append(error)

    if errors != []:
        error_message = f"Found {len(errors)} errors while checking BIDS subjects and sessions."
        if create_candidate or create_session:
            error_message += " No candidate or session has been created."

        log_error_exit(env, error_message)

    if candidate is None:
        log_error_exit(env, "No subject found in the BIDS dataset.")

    # Only commit the new candidates and sessions if no error has occured.
    env.db.commit()

    # Return the project ID of a candidate of the BIDS dataset. For this value to be used, it
    # should be assumed that all the candidates of the BIDS dataset are in the same project.
    return candidate.registration_project_id


def check_or_create_bids_subject_and_sessions(
    env: Env,
    subject: BidsSubject,
    create_candidate: bool,
    create_session: bool,
) -> DbCandidate:
    """
    Check that a BIDS subject and its sessions correspond to a LORIS candidate and its sessions, or
    create them using information extracted from the BIDS dataset if the relevant arguments are
    passed.

    Raise an error if the check or creation of the candidate or any of its sessions fail. Return
    the candidate corresponding to the BIDS subject.
    """

    tsv_participant = subject.root_dataset.get_tsv_participant(subject.label)
    if tsv_participant is None:
        raise CheckBidsSubjectSessionError(
            f"No participants.tsv entry found for subject label '{subject.label}' in the BIDS  dataset. The BIDS"
            " directory subjects do not match the participants.tsv file."
        )

    candidate = check_or_create_bids_subject(env, tsv_participant, create_candidate)

    if create_session:
        cohort = get_tsv_participant_cohort(env, tsv_participant)
    else:
        cohort = None

    for session in subject.sessions:
        if session.label is not None:
            visit_label = session.label
        else:
            visit_label = get_default_bids_visit_label_config(env)

        check_or_create_bids_session(env, candidate, cohort, visit_label, create_session)

    return candidate


def check_or_create_bids_subject(env: Env, tsv_participant: BidsTsvParticipant, create_candidate: bool) -> DbCandidate:
    """
    Check that the subject of a BIDS participants.tsv row exists in LORIS, or create them using the
    information of that row if the relevant argument is passed. Raise an exception if the candidate
    does not exist or cannot be created.
    """

    try:
        cand_id = int(tsv_participant.id)
        candidate = try_get_candidate_with_cand_id(env.db, cand_id)
        if candidate is None:
            raise CheckBidsSubjectSessionError(
                f"No LORIS candidate found for the BIDS participant ID '{tsv_participant.id}' (identified as a CandID)."
            )

        return candidate
    except ValueError:
        pass

    candidate = try_get_candidate_with_psc_id(env.db, tsv_participant.id)
    if candidate is not None:
        return candidate

    if not create_candidate:
        raise CheckBidsSubjectSessionError(
            f"No LORIS candidate found for the BIDS participant ID '{tsv_participant.id}' (identified as a PSCID)."
        )

    return create_bids_candidate(env, tsv_participant)


def create_bids_candidate(env: Env, tsv_participant: BidsTsvParticipant) -> DbCandidate:
    """
    Check a candidate using the information of a BIDS participants.tsv row, or raise an exception
    if that candidate cannot be created.
    """

    log(env, f"Creating LORIS candidate for BIDS subject '{tsv_participant.id}'...")

    psc_id = tsv_participant.id

    cand_id = generate_new_cand_id(env.db)

    birth_date = get_tsv_participant_birth_date(tsv_participant)

    sex = get_tsv_participant_sex(env, tsv_participant)

    site = get_tsv_participant_site(env, tsv_participant)

    project = get_tsv_participant_project(env, tsv_participant)

    log(
        env,
        (
            "Creating candidate with information:\n"
            f"  PSCID   = {psc_id}\n"
            f"  CandID  = {cand_id}\n"
            f"  Site    = {site.name}\n"
            f"  Project = {project.name}"
        )
    )

    now = datetime.now()

    candidate = DbCandidate(
        cand_id                 = cand_id,
        psc_id                  = psc_id,
        date_of_birth           = birth_date,
        sex                     = sex,
        registration_site_id    = site.id,
        registration_project_id = project.id,
        user_id                 = 'imaging.py',
        entity_type             = 'Human',
        date_active             = now,
        date_registered         = now,
        active                  = True,
    )

    env.db.add(candidate)
    env.db.flush()

    return candidate


def check_or_create_bids_session(
    env: Env,
    candidate: DbCandidate,
    cohort: DbCohort | None,
    visit_label: str,
    create_session: bool,
) -> DbSession:
    """
    Check that a BIDS session exists in LORIS, or create it using information previously obtained
    from the BIDS dataset if the relevant argument is passed. Raise an exception if the session
    does not exist or cannot be created.
    """

    session = try_get_session_with_cand_id_visit_label(env.db, candidate.cand_id, visit_label)
    if session is not None:
        return session

    if not create_session:
        log_error_exit(
            env,
            f"No session found for candidate '{candidate.psc_id}' and visit label '{visit_label}'."
        )

    return create_bids_session(env, candidate, cohort, visit_label)


def create_bids_session(env: Env, candidate: DbCandidate, cohort: DbCohort | None, visit_label: str) -> DbSession:
    """
    Create a session using information previously obtained from the BIDS dataset, or raise an
    exception if the session does not exist or cannot be created.
    """

    if cohort is None:
        log_error_exit(env, f"No cohort found for candidate '{candidate.psc_id}', cannot create session.")

    log(
        env,
        (
            "Creating session with:\n"
            f"  PSCID       = {candidate.cand_id}\n"
            f"  Visit label = {visit_label}"
        )
    )

    session = DbSession(
        candidate_id     = candidate.id,
        visit_label      = visit_label,
        current_stage    = 'Not Started',
        site_id          = candidate.registration_site_id,
        project_id       = candidate.registration_project_id,
        cohort_id        = cohort.id,
        scan_done        = True,
        submitted        = False,
        active           = True,
        user_id          = '',
        hardcopy_request = '-',
        mri_qc_status    = '',
        mri_qc_pending   = False,
        mri_caveat       = True,
    )

    env.db.add(session)
    env.db.flush()

    return session


def get_tsv_participant_birth_date(tsv_participant: BidsTsvParticipant) -> datetime | None:
    """
    Get the birth date of a BIDS participants.tsv row, or return `None` if no birth date is
    specified. Raise an exception if a birth date is specified but cannot be parsed.
    """

    if tsv_participant.birth_date is None:
        return None

    try:
        return parse(tsv_participant.birth_date)
    except ParserError:
        raise CheckBidsSubjectSessionError(
            f"Could not parse the BIDS participants.tsv birth date '{tsv_participant.birth_date}'."
        )


def get_tsv_participant_sex(env: Env, tsv_participant: BidsTsvParticipant) -> str | None:
    """
    Get the sex of a BIDS participants.tsv row, or return `None` if no sex is specified. Raise an
    exception if a sex is specified but does not exist in LORIS.
    """

    if tsv_participant.sex is None:
        return None

    tsv_participant_sex = tsv_participant.sex.lower()

    if tsv_participant_sex in ['m', 'male']:
        sex_name = 'Male'
    elif tsv_participant_sex in ['f', 'female']:
        sex_name = 'Female'
    elif tsv_participant_sex in ['o', 'other']:
        sex_name = 'Other'
    else:
        sex_name = tsv_participant.sex

    sex = try_get_sex_with_name(env.db, sex_name)
    if sex is None:
        raise CheckBidsSubjectSessionError(
            f"No LORIS sex found for the BIDS participants.tsv sex name or alias '{tsv_participant.sex}'."
        )

    return sex.name


def get_tsv_participant_site(env: Env, tsv_participant: BidsTsvParticipant) -> DbSite:
    """
    Get the site of a BIDS participants.tsv row, or raise an exception if no site is specified or
    the site does not exist in LORIS.
    """

    if tsv_participant.site is None:
        raise CheckBidsSubjectSessionError(
            "No 'site' column found in the BIDS participants.tsv file, this field is required to create candidates or"
            " sessions. "
        )

    site = try_get_site_with_name(env.db, tsv_participant.site)
    if site is not None:
        return site

    site = try_get_site_with_alias(env.db, tsv_participant.site)
    if site is not None:
        return site

    raise CheckBidsSubjectSessionError(
        f"No site found for the BIDS participants.tsv site name or alias '{tsv_participant.site}'."
    )


def get_tsv_participant_project(env: Env, tsv_participant: BidsTsvParticipant) -> DbProject:
    """
    Get the project of a BIDS participants.tsv row, or raise an exception if no project is
    specified or the project does not exist in LORIS.
    """

    if tsv_participant.project is None:
        raise CheckBidsSubjectSessionError(
            "No 'project' column found in the BIDS participants.tsv file, this field is required to create candidates"
            " or sessions. "
        )

    project = try_get_project_with_name(env.db, tsv_participant.project)
    if project is not None:
        return project

    project = try_get_project_with_alias(env.db, tsv_participant.project)
    if project is not None:
        return project

    raise CheckBidsSubjectSessionError(
        f"No project found for the BIDS participants.tsv project name or alias '{tsv_participant.project}'."
    )


def get_tsv_participant_cohort(env: Env, tsv_participant: BidsTsvParticipant) -> DbCohort:
    """
    Get the cohort of a BIDS participants.tsv row, or raise an exception if no cohort is specified
    or the cohort does not exist in LORIS.
    """

    if tsv_participant.cohort is None:
        raise CheckBidsSubjectSessionError(
            "No 'cohort' column found in the BIDS participants.tsv file, this field is required to create session."
        )

    cohort = try_get_cohort_with_name(env.db, tsv_participant.cohort)
    if cohort is None:
        raise CheckBidsSubjectSessionError(
            f"No cohort found for the BIDS participants.tsv cohort name '{tsv_participant.cohort}'."
        )

    return cohort


# TODO: Move this function to a more appropriate place.
def generate_new_cand_id(db: Database) -> int:
    """
    Generate a new random CandID that is not already in the database.
    """

    while True:
        cand_id = random.randint(100000, 999999)
        candidate = try_get_candidate_with_cand_id(db, cand_id)
        if candidate is None:
            return cand_id
