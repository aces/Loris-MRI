from lib.db.models.candidate import DbCandidate
from lib.db.models.cohort import DbCohort
from lib.db.models.session import DbSession
from lib.db.queries.cohort import try_get_cohort_with_name
from lib.db.queries.project import try_get_project_cohort_with_project_id_cohort_id
from lib.db.queries.session import try_get_session_with_cand_id_visit_label
from lib.db.queries.visit import try_get_visit_window_with_visit_label, try_get_visit_with_visit_label
from lib.env import Env
from lib.logging import log
from sqlalchemy import func, select

from loris_bids_importer.config import BidsSessionConfig, CreateBidsSessionConfig
from loris_bids_importer.resolution.candidates import get_project, get_site


def resolve_bids_session(env: Env, candidate: DbCandidate, config: BidsSessionConfig) -> DbSession:
    """
    Get or create the LORIS session described by a BIDS session configuration.
    """

    if config.visit_label == '':
        raise Exception("Session configuration must contain a non-empty visit label.")

    session = try_get_session_with_cand_id_visit_label(env.db, candidate.cand_id, config.visit_label)
    if session is not None:
        return session

    if config.create is None:
        raise Exception(
            f"No LORIS session found for candidate '{candidate.psc_id}' and visit label"
            f" '{config.visit_label}'."
        )

    return create_bids_session(env, candidate, config.visit_label, config.create)


def create_bids_session(
    env: Env,
    candidate: DbCandidate,
    visit_label: str,
    config: CreateBidsSessionConfig,
) -> DbSession:
    """
    Create a LORIS session using a BIDS session creation configuration.
    """

    visit = try_get_visit_with_visit_label(env.db, visit_label)
    if visit is None:
        raise Exception(f"No LORIS visit found for visit label '{visit_label}'.")

    visit_window = try_get_visit_window_with_visit_label(env.db, visit_label)
    if visit_window is None:
        raise Exception(f"No LORIS visit window found for visit label '{visit_label}'.")

    project = get_project(env, config.project)
    site = get_site(env, config.site)
    cohort = get_cohort(env, config.cohort)

    project_cohort = try_get_project_cohort_with_project_id_cohort_id(env.db, project.id, cohort.id)
    if project_cohort is None:
        raise Exception(
            f"No association found between LORIS project '{project.name}' and cohort '{cohort.name}'."
        )

    log(
        env,
        (
            "Creating session with information:\n"
            f"  PSCID       = {candidate.psc_id}\n"
            f"  Visit label = {visit.label}\n"
            f"  Site        = {site.name}\n"
            f"  Project     = {project.name}\n"
            f"  Cohort      = {cohort.name}"
        ),
    )

    session = DbSession(
        candidate_id = candidate.id,
        visit_label  = visit.label,
        visit_number = get_candidate_next_visit_number(env, candidate),
        site_id      = site.id,
        project_id   = project.id,
        cohort_id    = cohort.id,
    )

    env.db.add(session)
    env.db.flush()
    return session


def get_candidate_next_visit_number(env: Env, candidate: DbCandidate) -> int:
    """
    Get the next visit number for a candidate, including sessions flushed during this import.
    """

    visit_number = env.db.execute(
        select(func.max(DbSession.visit_number))
        .where(DbSession.candidate_id == candidate.id)
    ).scalar_one_or_none()

    return (visit_number or 0) + 1


def get_cohort(env: Env, name: str) -> DbCohort:
    """
    Get a LORIS cohort by name.
    """

    cohort = try_get_cohort_with_name(env.db, name)
    if cohort is None:
        raise Exception(f"No LORIS cohort found for name '{name}'.")

    return cohort
