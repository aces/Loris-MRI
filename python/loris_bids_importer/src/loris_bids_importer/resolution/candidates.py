from datetime import datetime

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

from loris_bids_importer.config import BidsCandidateConfig, CreateBidsCandidateConfig


def resolve_bids_candidate(env: Env, config: BidsCandidateConfig) -> DbCandidate:
    """
    Get or create the LORIS candidate described by a BIDS candidate configuration.
    """

    if config.cand_id is not None:
        candidate = try_get_candidate_with_cand_id(env.db, config.cand_id)
        if candidate is None:
            raise Exception(f"No LORIS candidate found for CandID {config.cand_id}.")

        if config.psc_id is not None and candidate.psc_id != config.psc_id:
            raise Exception(
                f"Candidate configuration CandID and PSCID mismatch: CandID {config.cand_id} belongs to PSCID"
                f" '{candidate.psc_id}', not '{config.psc_id}'."
            )

        return candidate

    if config.psc_id is not None:
        candidate = try_get_candidate_with_psc_id(env.db, config.psc_id)
        if candidate is not None:
            return candidate

        if config.create is None:
            raise Exception(f"No LORIS candidate found for PSCID '{config.psc_id}'.")

        return create_bids_candidate(env, config.psc_id, config.create)

    raise Exception("Candidate configuration must contain a CandID or PSCID.")


def create_bids_candidate(
    env: Env,
    psc_id: str,
    config: CreateBidsCandidateConfig,
) -> DbCandidate:
    """
    Create a LORIS candidate using a BIDS candidate creation configuration.
    """

    if psc_id == '':
        raise Exception("Cannot create a candidate with an empty PSCID.")

    project = get_project(env, config.registration_project)
    site    = get_site(env, config.registration_site)
    sex     = get_sex(env, config.sex)
    cand_id = generate_new_cand_id(env)

    log(
        env,
        (
            "Creating candidate with information:\n"
            f"  PSCID   = {psc_id}\n"
            f"  CandID  = {cand_id}\n"
            f"  Site    = {site.name}\n"
            f"  Project = {project.name}"
        ),
    )

    now = datetime.now()
    candidate = DbCandidate(
        cand_id                 = cand_id,
        psc_id                  = psc_id,
        external_id             = config.external_id,
        date_of_birth           = config.date_of_birth,
        sex                     = sex,
        registration_site_id    = site.id,
        registration_project_id = project.id,
        user_id                 = 'imaging.py',
        date_active             = now,
        date_registered         = now,
    )

    env.db.add(candidate)
    env.db.flush()
    return candidate


def get_project(env: Env, value: str) -> DbProject:
    """
    Get a LORIS project by name or alias.
    """

    project = try_get_project_with_name(env.db, value)
    if project is None:
        project = try_get_project_with_alias(env.db, value)

    if project is None:
        raise Exception(f"No LORIS project found for name or alias '{value}'.")

    return project


def get_site(env: Env, value: str) -> DbSite:
    """
    Get a LORIS site by name or alias.
    """

    site = try_get_site_with_name(env.db, value)
    if site is None:
        site = try_get_site_with_alias(env.db, value)

    if site is None:
        raise Exception(f"No LORIS site found for name or alias '{value}'.")

    return site


def get_sex(env: Env, value: str | None) -> str | None:
    """
    Get a LORIS sex name from a LORIS or standard BIDS sex value.
    """

    if value is None:
        return None

    match value.lower():
        case 'm' | 'male':
            name = 'Male'
        case 'f' | 'female':
            name = 'Female'
        case 'o' | 'other':
            name = 'Other'
        case _:
            name = value

    sex = try_get_sex_with_name(env.db, name)
    if sex is None:
        raise Exception(f"No LORIS sex found for name or BIDS value '{value}'.")

    return sex.name
