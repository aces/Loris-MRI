from loris_bids_reader.files.participants import BidsParticipantTsvRow
from loris_bids_reader.info import BidsSessionInfo
from loris_utils.error import group_errors

from lib.config import get_default_bids_visit_label_config
from lib.db.models.candidate import DbCandidate
from lib.db.models.cohort import DbCohort
from lib.db.models.session import DbSession
from lib.db.queries.cohort import try_get_cohort_with_name
from lib.db.queries.session import try_get_session_with_cand_id_visit_label
from lib.env import Env
from lib.import_bids_dataset.check_subjects import check_or_create_bids_subject
from lib.logging import log


def check_or_create_bids_sessions(
    env: Env,
    session_infos: list[BidsSessionInfo],
    create_session: bool,
) -> list[DbSession]:
    """
    Check that the sessions of a BIDS dataset exist in LORIS, or create then using their BIDS
    `participants.tsv` row information if candidate creation is enabled. Raise an exception if any
    candidate does not exist and cannot be created.
    """

    return group_errors(
        "Could not get or create the LORIS sessions for the BIDS dataset.",
        (lambda: check_or_create_bids_session(env, session_info, create_session) for session_info in session_infos),
    )


def check_or_create_bids_session(
    env: Env,
    session_info: BidsSessionInfo,
    create_session: bool,
) -> DbSession:
    """
    Check that a BIDS session exists in LORIS, or create it using information previously obtained
    from the BIDS dataset if the relevant argument is passed. Raise an exception if the session
    does not exist or cannot be created.
    """

    candidate = check_or_create_bids_subject(env, session_info)

    if session_info.session is not None:
        visit_label = session_info.session
    else:
        visit_label = get_default_bids_visit_label_config(env)

    if visit_label is None:
        raise Exception(
            "No session label found in the BIDS dataset, and no default session found in the LORIS configuration."
        )

    session = try_get_session_with_cand_id_visit_label(env.db, candidate.cand_id, visit_label)
    if session is not None:
        return session

    if not create_session:
        raise Exception(
            f"No session found for candidate '{candidate.psc_id}' and visit label '{visit_label}'."
        )

    if session_info.participant_row is None:
        raise Exception(
            f"Cannot create LORIS session for session '{session_info.subject}' since it does not have a row in the"
            " BIDS `participants.tsv` file."
        )

    return create_bids_session(env, candidate, session_info.participant_row, visit_label)


def create_bids_session(
    env: Env,
    candidate: DbCandidate,
    participant: BidsParticipantTsvRow,
    visit_label: str,
) -> DbSession:
    """
    Create a session using information obtained from a BIDS dataset, or raise an exception if the
    session does not exist or cannot be created.
    """

    cohort = get_bids_participant_row_cohort(env, participant)

    log(
        env,
        (
            "Creating session with:\n"
            f"  PSCID       = {candidate.psc_id}\n"
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


def get_bids_participant_row_cohort(env: Env, participant: BidsParticipantTsvRow) -> DbCohort:
    """
    Get the cohort of a BIDS `participants.tsv` row, or raise an exception if the cohort is not
    specified or does not exist in LORIS.
    """

    if participant.cohort is None:
        raise Exception(
            "No 'cohort' column found in the BIDS participants.tsv file, this field is required to create session."
        )

    cohort = try_get_cohort_with_name(env.db, participant.cohort)
    if cohort is None:
        raise Exception(
            f"No cohort found for the BIDS participants.tsv cohort name '{participant.cohort}'."
        )

    return cohort
