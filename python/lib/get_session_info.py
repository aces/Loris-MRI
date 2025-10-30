from dataclasses import dataclass
from typing import Never

from lib.config import get_patient_id_dicom_header_config
from lib.config_file import SessionCandidateConfig, SessionConfig, SessionPhantomConfig
from lib.db.models.candidate import DbCandidate
from lib.db.models.cohort import DbCohort
from lib.db.models.dicom_archive import DbDicomArchive
from lib.db.models.mri_scanner import DbMriScanner
from lib.db.models.project import DbProject
from lib.db.models.session import DbSession
from lib.db.models.site import DbSite
from lib.db.queries.candidate import try_get_candidate_with_cand_id
from lib.db.queries.cohort import try_get_cohort_with_name
from lib.db.queries.project import try_get_project_cohort_with_project_id_cohort_id, try_get_project_with_alias
from lib.db.queries.session import try_get_session_with_cand_id_visit_label
from lib.db.queries.site import try_get_site_with_alias
from lib.db.queries.visit import try_get_visit_window_with_visit_label, try_get_visit_with_visit_label
from lib.env import Env
from lib.imaging_lib.mri_scanner import MriScannerInfo, get_or_create_scanner


@dataclass
class SessionInfo:
    """
    Information about a session.
    """

    session: DbSession
    scanner: DbMriScanner


@dataclass
class CreateSessionInfo:
    """
    Information required to create a session.
    """

    site: DbSite
    project: DbProject
    cohort: DbCohort | None


class SessionConfigError(Exception):
    """
    Exception raised if a session configuration provided by the configuration file is incorrect.
    """

    def __init__(self, message: str):
        super().__init__(message)


# TODO: Move to a *new* `lib.dicom_archive` module later.
def get_dicom_archive_scanner_info(dicom_archive: DbDicomArchive) -> MriScannerInfo:
    """
    Get the scanner information of a DICOM archive database object.
    """

    return MriScannerInfo(
        manufacturer     = dicom_archive.scanner_manufacturer     or None,
        model            = dicom_archive.scanner_model            or None,
        serial_number    = dicom_archive.scanner_serial_number    or None,
        software_version = dicom_archive.scanner_software_version or None,
    )


# TODO: Move to a *new* `lib.dicom_archive` module later.
def get_dicom_archive_session_info(env: Env, dicom_archive: DbDicomArchive) -> SessionInfo:
    """
    Get the session information for a DICOM archive database object using the session
    identification configuration function, or raise a `SessionConfigError` if the configuration
    returned is incorrect.
    """

    patient_id_dicom_header = get_patient_id_dicom_header_config(env)
    match patient_id_dicom_header:
        case 'PatientID':
            patient_id = dicom_archive.patient_id
        case 'PatientName':
            patient_id = dicom_archive.patient_name

    scanner_info = get_dicom_archive_scanner_info(dicom_archive)

    return get_session_info(env, patient_id, scanner_info)


def get_session_info(env: Env, patient_id: str, scanner_info: MriScannerInfo) -> SessionInfo:
    """
    Get the session information for a patient ID using the session identification configuration
    function, or raise a `SessionConfigError` if the configuration returned is incorrect.
    """

    try:
        get_session_config = env.config_info.get_session_config
    except AttributeError:
        raise SessionConfigError("Function `get_session_config` not found in the Python configuration file.")

    session_config = get_session_config(env.db, patient_id)

    if session_config is None:
        raise SessionConfigError(
            f"No session returned by function `get_session_config` for patient ID '{patient_id}'."
        )

    return get_session_config_info(env, session_config, scanner_info)


def get_session_config_info(env: Env, session_config: SessionConfig, scanner_info: MriScannerInfo) -> SessionInfo:
    """
    Get the session information for a session configuration, or raise a `SessionConfigError` if
    that configuration is incorrect.
    """

    match session_config:
        case SessionCandidateConfig():
            return get_candidate_session_info(env, session_config, scanner_info)
        case SessionPhantomConfig():
            return get_phantom_session_info(env, session_config, scanner_info)


def get_candidate_session_info(
    env: Env,
    session_config: SessionCandidateConfig,
    scanner_info: MriScannerInfo,
) -> SessionInfo:
    """
    Get the session information for a candidate session configuratution, or raise a
    `SessionConfigError` if that configuration is incorrect.
    """

    candidate = try_get_candidate_with_cand_id(env.db, session_config.cand_id)

    if candidate is None:
        raise_session_config_error(
            session_config,
            f"No candidate found for CandID {session_config.cand_id}."
        )

    if candidate.psc_id != session_config.psc_id:
        raise_session_config_error(
            session_config,
            (
                f"Session PSCID and CandID mismatch. No candidate has both CandID {candidate.cand_id} and PSCID"
                f" '{candidate.psc_id}'."
            )
        )

    visit = try_get_visit_with_visit_label(env.db, session_config.visit_label)
    if visit is None:
        raise_session_config_error(
            session_config,
            f"No visit found for visit label '{session_config.visit_label}'."
        )

    session = try_get_session_with_cand_id_visit_label(env.db, session_config.cand_id, session_config.visit_label)
    if session is None:
        visit_number = get_candidate_next_visit_number(candidate)
        create_session_info = get_candidate_create_session_info(env, session_config)
        session = create_session(env, candidate, create_session_info, visit.label, visit_number)

    scanner = get_or_create_scanner(env, scanner_info, session.site_id, session.project_id)

    return SessionInfo(session, scanner)


def get_candidate_create_session_info(env: Env, session_config: SessionCandidateConfig) -> CreateSessionInfo:
    """
    Get the session creation information for a candidate session configuration, or raise a
    `SessionConfigError` if that configuration is incorrect.
    """

    if session_config.create_session is None:
        raise_session_config_error(
            session_config,
            f"No session found for candidate {session_config.cand_id} and visit label '{session_config.visit_label}'."
        )

    visit_window = try_get_visit_window_with_visit_label(env.db, session_config.visit_label)
    if visit_window is None:
        raise_session_config_error(
            session_config,
            f"No visit window found for visit '{session_config.visit_label}'."
        )

    site    = get_session_site(env, session_config, session_config.create_session.site)
    project = get_session_project(env, session_config, session_config.create_session.project)
    cohort  = get_session_cohort(env, session_config, session_config.create_session.cohort)

    project_cohort = try_get_project_cohort_with_project_id_cohort_id(env.db, project.id, cohort.id)
    if project_cohort is None:
        raise_session_config_error(
            session_config,
            f"No association found for project '{project.name}' and cohort '{cohort.name}'."
        )

    return CreateSessionInfo(
        site    = site,
        project = project,
        cohort  = cohort,
    )


def get_phantom_session_info(
    env: Env,
    session_config: SessionPhantomConfig,
    scanner_info: MriScannerInfo,
) -> SessionInfo:
    """
    Get the session information for a phantom session configuratution, or raise a
    `SessionConfigError` if that configuration is incorrect.
    """

    create_session_info = get_phantom_create_session_info(env, session_config)
    scanner = get_or_create_scanner(env, scanner_info, create_session_info.site.id, create_session_info.project.id)
    session = create_session(env, scanner.candidate, create_session_info, session_config.name, 1)

    return SessionInfo(session, scanner)


def get_phantom_create_session_info(env: Env, session_config: SessionPhantomConfig) -> CreateSessionInfo:
    """
    Get the session creation information for a phantom session configuration, or raise a
    `SessionConfigError` if that configuration is incorrect.
    """

    site    = get_session_site(env, session_config, session_config.site)
    project = get_session_project(env, session_config, session_config.project)

    return CreateSessionInfo(
        site    = site,
        project = project,
        cohort  = None
    )


def create_session(
    env: Env,
    candidate: DbCandidate,
    create_session_info: CreateSessionInfo,
    visit_label: str,
    visit_number: int,
) -> DbSession:
    """
    Create a session based on the parameters provided.
    """

    session = DbSession(
        candidate_id     = candidate.id,
        visit_label      = visit_label,
        visit_number     = visit_number,
        site_id          = create_session_info.site.id,
        current_stage    = 'Not Started',
        scan_done        = True,
        submitted        = False,
        project_id       = create_session_info.project.id,
        cohort_id        = create_session_info.cohort.id if create_session_info.cohort is not None else None,
        active           = True,
        user_id          = '',
        hardcopy_request = '-',
        mri_qc_status    = '',
        mri_qc_pending   = False,
        mri_caveat       = 'true',
    )

    env.db.add(session)
    env.db.commit()

    return session


def get_session_site(env: Env, session_config: SessionConfig, site_alias: str) -> DbSite:
    """
    Get the site for a session configuration site alias, or raise a `SessionConfigError` if that
    alias is incorrect.
    """

    site = try_get_site_with_alias(env.db, site_alias)
    if site is None:
        raise_session_config_error(session_config, f"No site found for site alias '{site_alias}'.")

    return site


def get_session_project(env: Env, session_config: SessionConfig, project_alias: str) -> DbProject:
    """
    Get the project for a session configuration project alias, or raise a `SessionConfigError` if
    that alias is incorrect.
    """

    project = try_get_project_with_alias(env.db, project_alias)
    if project is None:
        raise_session_config_error(session_config, f"No project found for project alias '{project_alias}'.")

    return project


def get_session_cohort(env: Env, session_config: SessionConfig, cohort_name: str) -> DbCohort:
    """
    Get the cohort for a session configuration cohort name, or raise a `SessionConfigError` if that
    name is incorrect.
    """

    cohort = try_get_cohort_with_name(env.db, cohort_name)
    if cohort is None:
        raise_session_config_error(session_config, f"No cohort found for cohort name '{cohort_name}'.")

    return cohort


def get_candidate_next_visit_number(candidate: DbCandidate) -> int:
    """
    Get the next visit number for a new session for a given candidate.
    """

    visit_numbers = [
        session.visit_number
        for session in candidate.sessions
        if session.visit_number is not None
    ]

    return max(*visit_numbers, 0) + 1


def raise_session_config_error(session_config: SessionConfig, message: str) -> Never:
    """
    Raise a session configuration error for a given session configuration.
    """

    match session_config:
        case SessionCandidateConfig():
            session_name = f"{session_config.psc_id} / {session_config.cand_id} / {session_config.visit_label}"
        case SessionPhantomConfig():
            session_name = session_config.name

    raise SessionConfigError(f"Configuration error for session ({session_name}):\n{message}")
