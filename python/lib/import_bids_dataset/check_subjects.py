from datetime import datetime

from loris_bids_reader.files.participants import BidsParticipantTsvRow
from loris_bids_reader.info import BidsSubjectInfo
from loris_utils.error import group_errors, group_errors_tuple
from loris_utils.parse import try_parse_int

from lib.candidate import generate_new_cand_id
from lib.db.models.candidate import DbCandidate
from lib.db.models.project import DbProject
from lib.db.models.site import DbSite
from lib.db.queries.candidate import try_get_candidate_with_cand_id, try_get_candidate_with_psc_id
from lib.db.queries.project import try_get_project_with_alias, try_get_project_with_name
from lib.db.queries.sex import try_get_sex_with_name
from lib.db.queries.site import try_get_site_with_alias, try_get_site_with_name
from lib.env import Env
from lib.logging import log


def check_or_create_bids_subjects(
    env: Env,
    subject_infos: list[BidsSubjectInfo],
    create_candidate: bool = False,
) -> list[DbCandidate]:
    """
    Check that the candidates of a BIDS dataset exist in LORIS, or create then using the BIDS
    metadata information if candidate creation is enabled. Raise an exception if any candidate
    does not exist and cannot be created.
    """

    return group_errors(
        "Could not get or create the LORIS candidates for the BIDS dataset.",
        (lambda: check_or_create_bids_subject(env, subject_info, create_candidate) for subject_info in subject_infos),
    )


def check_or_create_bids_subject(
    env: Env,
    subject_info: BidsSubjectInfo,
    create_candidate: bool = False,
) -> DbCandidate:
    """
    Check that the candidate of a BIDS dataset exists in LORIS, or create them using its BIDS
    metadata information if candidate creation is enabled. Raise an exception if the candidate
    does not exist and cannot be created.
    """

    cand_id = try_parse_int(subject_info.subject)
    if cand_id is not None:
        candidate = try_get_candidate_with_cand_id(env.db, cand_id)
        if candidate is None:
            raise Exception(
                f"No LORIS candidate found for the BIDS subject label '{subject_info.subject}'"
                " (identified as a CandID)."
            )

        return candidate

    candidate = try_get_candidate_with_psc_id(env.db, subject_info.subject)
    if candidate is not None:
        return candidate

    if not create_candidate:
        raise Exception(
            f"No LORIS candidate found for the BIDS subject label '{subject_info.subject}'"
            " (identified as a PSCID)."
        )

    if subject_info.participant_row is None:
        raise Exception(
            f"Cannot create LORIS candidate for subject '{subject_info.subject}' since it does not have a row in the"
            " BIDS `participants.tsv` file."
        )

    return create_bids_candidate(env, subject_info.participant_row)


def create_bids_candidate(env: Env, participant: BidsParticipantTsvRow) -> DbCandidate:
    """
    Create a candidate using the information obtained from a BIDS `participants.tsv` row, or raise
    an exception if that candidate cannot be created.
    """

    log(env, f"Creating LORIS candidate for BIDS subject '{participant.participant_id}'...")

    psc_id = participant.participant_id
    cand_id = generate_new_cand_id(env)

    project, site, sex = group_errors_tuple(
        f"Could not get information to create candidate '{participant.participant_id}'.",
        lambda: get_bids_participant_row_project(env, participant),
        lambda: get_bids_participant_row_site(env, participant),
        lambda: get_bids_participant_row_sex(env, participant),
    )

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
        date_of_birth           = participant.birth_date,
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


def get_bids_participant_row_sex(env: Env, participant: BidsParticipantTsvRow) -> str | None:
    """
    Get the sex of a BIDS `participants.tsv` row, or return `None` if the sex is not specified.
    Raise an exception if a sex is specified but does not exist in LORIS.
    """

    if 'sex' not in participant.data:
        return None

    tsv_participant_sex = participant.data['sex'].lower()

    if tsv_participant_sex in ['m', 'male']:
        sex_name = 'Male'
    elif tsv_participant_sex in ['f', 'female']:
        sex_name = 'Female'
    elif tsv_participant_sex in ['o', 'other']:
        sex_name = 'Other'
    else:
        sex_name = participant.data['sex']

    sex = try_get_sex_with_name(env.db, sex_name)
    if sex is None:
        raise Exception(
            f"No LORIS sex found for the BIDS participants.tsv sex name or alias '{participant.data['sex']}'."
        )

    return sex.name


def get_bids_participant_row_site(env: Env, participant: BidsParticipantTsvRow) -> DbSite:
    """
    Get the site of a BIDS `participants.tsv` row, or raise an exception if the site is not
    specified or does not exist in LORIS.
    """

    if 'site' not in participant.data:
        raise Exception(
            "No 'site' column found in the BIDS participants.tsv file, this field is required to create candidates or"
            " sessions. "
        )

    site = try_get_site_with_name(env.db, participant.data['site'])
    if site is not None:
        return site

    site = try_get_site_with_alias(env.db, participant.data['site'])
    if site is not None:
        return site

    raise Exception(
        f"No site found for the BIDS participants.tsv site name or alias '{participant.data['site']}'."
    )


def get_bids_participant_row_project(env: Env, participant: BidsParticipantTsvRow) -> DbProject:
    """
    Get the project of a BIDS `participants.tsv` row, or raise an exception if the project is not
    specified or does not exist in LORIS.
    """

    if 'project' not in participant.data:
        raise Exception(
            "No 'project' column found in the BIDS participants.tsv file, this field is required to create candidates"
            " or sessions. "
        )

    project = try_get_project_with_name(env.db, participant.data['project'])
    if project is not None:
        return project

    project = try_get_project_with_alias(env.db, participant.data['project'])
    if project is not None:
        return project

    raise Exception(
        f"No project found for the BIDS participants.tsv project name or alias '{participant.data['project']}'."
    )
