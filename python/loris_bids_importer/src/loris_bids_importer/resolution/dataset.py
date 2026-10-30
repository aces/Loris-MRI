from dataclasses import dataclass
from datetime import date
from typing import cast

from lib.db.models.candidate import DbCandidate
from lib.db.models.session import DbSession
from lib.env import Env
from loris_bids_utils.labels import BidsSubjectLabel, BidsSubjectSessionLabel
from loris_bids_utils.reader import BidsDatasetReader, BidsSessionReader, BidsSubjectReader
from loris_utils.error import group_errors

from loris_bids_importer.config import (
    BidsCandidateConfig,
    BidsConfigError,
    BidsConfigFunctions,
    BidsSessionConfig,
    CreateBidsCandidateConfig,
)
from loris_bids_importer.resolution.candidates import resolve_bids_candidate
from loris_bids_importer.resolution.sessions import resolve_bids_session


@dataclass
class BidsLorisMappings:
    """
    Mappings from BIDS subject and session labels to LORIS candidates and sessions.
    """

    candidates: dict[BidsSubjectLabel, DbCandidate]
    sessions: dict[BidsSubjectSessionLabel, DbSession]


def resolve_bids_mappings(env: Env, bids: BidsDatasetReader, config: BidsConfigFunctions) -> BidsLorisMappings:
    """
    Configure and resolve the LORIS candidate and session mappings of a BIDS dataset.

    Database changes are flushed but not committed. Any error rolls back all changes performed by
    this resolution.
    """

    try:
        all_candidate_configs = group_errors(
            "Could not get the LORIS candidate configurations for the BIDS dataset.",
            (
                lambda: get_bids_candidate_config(env, config, bids_subject)
                for bids_subject in bids.subjects
            ),
        )

        # Map BIDS subject labels to their candidate configurations and remove filtered out
        # subjects.
        candidate_configs = {
            subject.label: candidate_config
            for subject, candidate_config in zip(bids.subjects, all_candidate_configs, strict=True)
            if candidate_config is not None
        }

        # Filter out BIDS sessions whose BIDS subjects have been filtered out.
        bids_sessions = [
            session for session in bids.sessions
            if session.subject.label in candidate_configs
        ]

        all_session_configs = group_errors(
            "Could not get the LORIS session configurations for the BIDS dataset.",
            (
                lambda: get_bids_session_config(
                    env,
                    config,
                    bids_session,
                    candidate_configs[bids_session.subject.label],
                )
                for bids_session in bids_sessions
            ),
        )

        # Map BIDS session labels to their session configurations and remove filtered out sessions.
        session_configs = [
            (session, session_config)
            for session, session_config in zip(bids_sessions, all_session_configs, strict=True)
            if session_config is not None
        ]

        # Get the list of BIDS subjects that have at least one session configuration that is not
        # filtered out.
        session_subject_labels = {session.subject.label for session, _ in session_configs}
        bids_subjects = [
            subject for subject in bids.subjects if subject.label in session_subject_labels
        ]

        candidates = group_errors(
            "Could not get or create the LORIS candidates for the BIDS dataset.",
            (
                lambda: resolve_bids_candidate_with_error(env, subject, candidate_configs[subject.label])
                for subject in bids_subjects
            ),
        )

        # Map BIDS subject labels to their LORIS candidates.
        candidate_mappings = {
            subject.label: candidate
            for subject, candidate in zip(bids_subjects, candidates, strict=True)
        }

        sessions = group_errors(
            "Could not get or create the LORIS sessions for the BIDS dataset.",
            (
                lambda: resolve_bids_session_with_error(
                    env,
                    bids_session,
                    candidate_mappings[bids_session.subject.label],
                    session_config,
                )
                for bids_session, session_config in session_configs
            ),
        )

        # Map BIDS session labels to their LORIS sessions.
        session_mappings = {
            bids_session.subject_session_label: session
            for (bids_session, _), session in zip(session_configs, sessions, strict=True)
        }

        return BidsLorisMappings(candidate_mappings, session_mappings)

    except BaseException:
        env.db.rollback()
        raise


def get_bids_candidate_config(
    env: Env,
    config: BidsConfigFunctions,
    bids_subject: BidsSubjectReader,
) -> BidsCandidateConfig | None:
    """
    Call and validate the candidate configuration function for a BIDS subject.
    """

    try:
        candidate_config = cast(
            object,
            config.get_candidate(env, bids_subject.label, bids_subject.participant_row),
        )
    except Exception as error:
        raise BidsConfigError(
            f"Could not get candidate configuration for BIDS subject '{bids_subject.label}': {error}"
        ) from error

    # Filter out BIDS subjects for which the configuration function returns `None`.
    if candidate_config is None:
        return None

    if not isinstance(candidate_config, BidsCandidateConfig):
        raise BidsConfigError(
            f"Candidate configuration function returned '{type(candidate_config).__name__}' for BIDS subject"
            f" '{bids_subject.label}', expected `BidsCandidateConfig` or `None`."
        )

    try:
        validate_bids_candidate_config(candidate_config)
    except BidsConfigError as error:
        raise BidsConfigError(
            f"Invalid candidate configuration for BIDS subject '{bids_subject.label}': {error}"
        ) from error

    return candidate_config


def validate_bids_candidate_config(config: BidsCandidateConfig):
    """
    Validate candidate configuration structure without querying or changing the database.
    """

    if config.cand_id is None and config.psc_id is None:
        raise BidsConfigError("Candidate configuration must contain a CandID or PSCID.")

    if config.cand_id is not None and type(config.cand_id) is not int:
        raise BidsConfigError("CandID must be an integer.")

    if config.psc_id is not None and (not isinstance(cast(object, config.psc_id), str) or config.psc_id == ''):
        raise BidsConfigError("PSCID must be a non-empty string.")

    if config.create is None:
        return

    if not isinstance(cast(object, config.create), CreateBidsCandidateConfig):
        raise BidsConfigError("Candidate creation settings must be a `CreateBidsCandidateConfig`.")

    if config.psc_id is None:
        raise BidsConfigError("Candidate creation requires a PSCID.")

    for field in ('registration_project', 'registration_site'):
        value = getattr(config.create, field)
        if not isinstance(value, str) or value == '':
            raise BidsConfigError(f"Candidate creation {field} must be a non-empty string.")

    for field in ('sex', 'external_id'):
        value = getattr(config.create, field)
        if value is not None and not isinstance(value, str):
            raise BidsConfigError(f"Candidate creation {field} must be a string or `None`.")

    if config.create.date_of_birth is not None and not isinstance(cast(object, config.create.date_of_birth), date):
        raise BidsConfigError("Candidate creation date_of_birth must be a date or `None`.")


def get_bids_session_config(
    env: Env,
    config: BidsConfigFunctions,
    bids_session: BidsSessionReader,
    candidate_config: BidsCandidateConfig,
) -> BidsSessionConfig | None:
    """
    Call and validate the session configuration function for a BIDS session.
    """

    name = bids_session.subject_session_label.display_name

    try:
        session_config = cast(
            object,
            config.get_session(
                env,
                candidate_config,
                bids_session.subject.label,
                bids_session.label,
                bids_session.subject.participant_row,
                bids_session.session_row,
            ),
        )
    except Exception as error:
        raise BidsConfigError(f"Could not get session configuration for BIDS session '{name}': {error}") from error

    if session_config is None:
        return None

    if not isinstance(session_config, BidsSessionConfig):
        raise BidsConfigError(
            f"Session configuration function returned '{type(session_config).__name__}' for BIDS session"
            f" '{name}', expected `BidsSessionConfig` or `None`."
        )

    return session_config


def resolve_bids_candidate_with_error(
    env: Env,
    bids_subject: BidsSubjectReader,
    config: BidsCandidateConfig,
) -> DbCandidate:
    """
    Get or create the LORIS candidate described by a BIDS candidate configuration.

    If an exception is raised, add contextual information to that exception.
    """

    try:
        return resolve_bids_candidate(env, config)
    except Exception as error:
        raise Exception(f"Could not resolve BIDS subject '{bids_subject.label}': {error}") from error


def resolve_bids_session_with_error(
    env: Env,
    bids_session: BidsSessionReader,
    candidate: DbCandidate,
    config: BidsSessionConfig,
) -> DbSession:
    """
    Get or create the LORIS session described by a BIDS session configuration.

    If an exception is raised, add contextual information to that exception.
    """

    try:
        return resolve_bids_session(env, candidate, config)
    except Exception as error:
        name = bids_session.subject_session_label.display_name
        raise Exception(f"Could not resolve BIDS session '{name}': {error}") from error
