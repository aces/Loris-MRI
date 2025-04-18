import random

from sqlalchemy.orm import Session as Database

import lib.exitcode
from lib.bidsreader import BidsReader
from lib.config import get_default_bids_visit_label_config
from lib.db.models.candidate import DbCandidate
from lib.db.models.cohort import DbCohort
from lib.db.models.session import DbSession
from lib.db.queries.candidate import try_get_candidate_with_cand_id, try_get_candidate_with_psc_id
from lib.db.queries.cohort import try_get_cohort_with_name
from lib.db.queries.project import try_get_project_with_name
from lib.db.queries.session import try_get_session_with_cand_id_visit_label
from lib.db.queries.site import get_all_sites, try_get_site_with_name
from lib.env import Env
from lib.import_bids_dataset.participant import BidsParticipant
from lib.logging import log, log_error_exit


def check_or_create_bids_candidates_and_sessions(
    env: Env,
    bids_reader: BidsReader,
    create_candidate: bool,
    create_session: bool,
) -> int:
    """
    Check that the candidates and sessions of a BIDS dataset exist in the LORIS database, or create
    them using the information of the BIDS dataset if the relevant arguments are passed. Exit the
    program with an error if a candidates or session cannot be created. Return the project ID of a
    candidate.
    """

    # Since there should awalys be participants, 0 will be overwritten.
    single_project_id = 0

    for bids_participant in bids_reader.bids_participants:

        candidate = check_or_create_bids_candidate(env, bids_participant, create_candidate)

        single_project_id = candidate.registration_project_id

        cohort = None
        if bids_participant.cohort is not None:
            cohort = try_get_cohort_with_name(env.db, bids_participant.cohort)

        bids_sessions = bids_reader.cand_sessions_list[bids_participant.id]

        if bids_sessions == []:
            default_visit_label = get_default_bids_visit_label_config(env)
            check_or_create_bids_session(env, candidate, cohort, default_visit_label, create_session)
        else:
            for bids_session in bids_sessions:
                check_or_create_bids_session(env, candidate, cohort, bids_session, create_session)

    env.db.commit()

    return single_project_id


def check_or_create_bids_candidate(env: Env, bids_participant: BidsParticipant, create_candidate: bool) -> DbCandidate:
    """
    Check that the candidate of a BIDS `participants.tsv` record exists in the LORIS database, or
    create them using the information of that record if the relevant argument is passed. Exit the
    program with an error if the candidate cannot be created.
    """

    try:
        cand_id = int(bids_participant.id)
    except ValueError:
        cand_id = None

    if cand_id is not None:
        candidate = try_get_candidate_with_cand_id(env.db, cand_id)
        if candidate is not None:
            return candidate

    candidate = try_get_candidate_with_psc_id(env.db, bids_participant.id)
    if candidate is not None:
        return candidate

    if not create_candidate:
        log_error_exit(
            env,
            f"Candidate '{bids_participant.id}' not found. You can retry with the --createcandidate option.",
            lib.exitcode.CANDIDATE_NOT_FOUND,
        )

    return create_bids_candidate(env, bids_participant)


def create_bids_candidate(env: Env, bids_participant: BidsParticipant) -> DbCandidate:
    """
    Create a candidate using the information of a `participants.tsv` record, or exit the program
    with an error if the candidate cannot be created.
    """

    psc_id = bids_participant.id
    cand_id = generate_new_cand_id(env.db)

    # TODO: Convert to `Optional[date]`
    birth_date = bids_participant.birth_date

    if bids_participant.sex is not None:
        # TODO: Check that the sex exists in the database
        sex = get_standard_sex_name(bids_participant.sex)
    else:
        sex = None

    site = None
    if bids_participant.site is not None:
        site = try_get_site_with_name(env.db, bids_participant.site)

    # If no site was found, try to extract it to match the PSCID with a site alias.
    if site is None:
        all_sites = get_all_sites(env.db)
        for all_site in all_sites:
            if all_site.alias in psc_id:
                site = all_site

    project = None
    if bids_participant.project is not None:
        project = try_get_project_with_name(env.db, bids_participant.project)

    if site is None:
        log_error_exit(
            env,
            (
                f"Could not find a site for candidate '{psc_id}'.\n"
                "Please check that your psc table contains a site with an"
                " alias matching the BIDS participant_id or a name matching the site mentioned in"
                " participants.tsv's site column."
            ),
            lib.exitcode.PROJECT_CUSTOMIZATION_FAILURE,
        )

    if project is None:
        log_error_exit(
            env,
            (
                f"Could not find a project for candidate '{cand_id}'\n."
                "Please check that your project table contains a project with a"
                " name matching the participants.tsv's project column"
            ),
            lib.exitcode.PROJECT_CUSTOMIZATION_FAILURE,
        )

    log(
        env,
        (
            "Creating candidate with:\n"
            f"PSCID     = {psc_id}\n"
            f"CandID    = {cand_id}\n"
            f"SiteID    = {site.id}\n"
            f"ProjectID = {project.id}"
        )
    )

    candidate = DbCandidate(
        cand_id                = cand_id,
        psc_id                 = psc_id,
        date_of_birth          = birth_date,
        sex                    = sex,
        registration_site_id   = site.id,
        registration_projec_id = project.id,
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
    Check that a session of a BIDS dataset exists the LORIS database, or create it using
    information previously obtained from that dataset if the relevant argument is passed. Exit the
    program with an error if the session cannot be created.
    """

    session = try_get_session_with_cand_id_visit_label(env.db, candidate.cand_id, visit_label)
    if session is not None:
        return session

    if not create_session:
        log_error_exit(
            env,
            f"No session found for candidate {candidate.cand_id} and visit label '{visit_label}'."
        )

    if cohort is None:
        log_error_exit(
            env,
            f"No cohort found for candidate {candidate.cand_id}, cannot create session.",
        )

    return create_bids_session(env, candidate, cohort, visit_label)


def create_bids_session(env: Env, candidate: DbCandidate, cohort: DbCohort, visit_label: str) -> DbSession:
    """
    Create a session using information previously obtained from a BIDS dataset, or exit the program
    with an error if the session cannot be created.
    """

    log(
        env,
        (
            "Creating visit with:\n"
            f"CandID      = {candidate.cand_id}\n"
            f"Visit label = {visit_label}"
        )
    )

    session = DbSession(
        cand_id       = candidate.cand_id,
        visit_label   = visit_label,
        current_stage = 'Not Started',
        site_id       = candidate.registration_site_id,
        project_id    = candidate.registration_project_id,
        cohort_id     = cohort.id,
    )

    env.db.add(session)
    env.db.flush()

    return session


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


def get_standard_sex_name(sex: str) -> str:
    """
    Convert a sex name to its standard value.
    """

    if sex.lower() in ['m', 'male']:
        return 'Male'

    if sex.lower() in ['f', 'female']:
        return 'Female'

    return sex
