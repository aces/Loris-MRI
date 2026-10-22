import importlib.util
from collections.abc import Callable
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from types import ModuleType
from typing import cast

from lib.env import Env
from loris_bids_utils.files.participants import BidsParticipantTsvRow
from loris_bids_utils.files.sessions import BidsSessionTsvRow
from loris_bids_utils.labels import BidsSessionLabel, BidsSubjectLabel
from loris_utils.parse import try_parse_int


@dataclass(frozen=True)
class CreateBidsCandidateConfig:
    """
    LORIS information required to create a candidate during a BIDS import.

    Project and site values may be LORIS names or aliases. Sex values may be LORIS names or the
    standard BIDS values `M`, `F`, and `O`.
    """

    registration_project: str
    registration_site: str
    sex: str | None = None
    date_of_birth: date | None = None
    external_id: str | None = None


@dataclass(frozen=True)
class BidsCandidateConfig:
    """
    Configuration used to get or create the LORIS candidate of a BIDS subject.

    At least one of `cand_id` and `psc_id` must be provided. Providing both requires both values to
    identify the same candidate. Candidate creation requires a PSCID and is enabled only when
    `create` is provided.
    """

    cand_id: int | None = None
    psc_id: str | None = None
    create: CreateBidsCandidateConfig | None = None


@dataclass(frozen=True)
class CreateBidsSessionConfig:
    """
    LORIS information required to create a session during a BIDS import.

    Project and site values may be LORIS names or aliases. Cohort values are LORIS cohort names.
    """

    project: str
    site: str
    cohort: str


@dataclass(frozen=True)
class BidsSessionConfig:
    """
    Configuration used to get or create the LORIS session of a BIDS session.

    Session creation is enabled only when `create` is provided.
    """

    visit_label: str
    create: CreateBidsSessionConfig | None = None


CandidateConfigFunction = Callable[
    [Env, BidsSubjectLabel, BidsParticipantTsvRow | None],
    BidsCandidateConfig | None,
]

SessionConfigFunction = Callable[
    [
        Env,
        BidsCandidateConfig,
        BidsSubjectLabel,
        BidsSessionLabel | None,
        BidsParticipantTsvRow | None,
        BidsSessionTsvRow | None,
    ],
    BidsSessionConfig | None,
]


@dataclass(frozen=True)
class BidsConfigFunctions:
    """
    Candidate and session configuration functions used by a BIDS import.

    Returning `None` skips the subject or session. Session functions receive the validated
    candidate configuration before any database records are resolved or created.
    """

    get_candidate: CandidateConfigFunction
    get_session: SessionConfigFunction


class BidsConfigError(Exception):
    """
    Error raised for an invalid BIDS import configuration file or value.
    """


def load_bids_config(path: Path | None) -> BidsConfigFunctions:
    """
    Load the BIDS configuration functions from a Python file, or return the built-in exact-label
    configuration functions when no file is provided.
    """

    if path is None:
        return BidsConfigFunctions(
            get_candidate = get_default_bids_candidate_config,
            get_session   = get_default_bids_session_config,
        )

    module = _load_bids_config_module(path)

    get_candidate = getattr(module, 'get_bids_candidate_config', None)
    if not callable(get_candidate):
        raise BidsConfigError(
            f"Function `get_bids_candidate_config` not found in BIDS configuration file '{path}'."
        )

    get_session = getattr(module, 'get_bids_session_config', None)
    if not callable(get_session):
        raise BidsConfigError(
            f"Function `get_bids_session_config` not found in BIDS configuration file '{path}'."
        )

    return BidsConfigFunctions(
        get_candidate = cast(CandidateConfigFunction, get_candidate),
        get_session   = cast(SessionConfigFunction, get_session),
    )


def get_default_bids_candidate_config(
    _env: Env,
    subject_label: BidsSubjectLabel,
    _participant_row: BidsParticipantTsvRow | None,
) -> BidsCandidateConfig:
    """
    Map a BIDS subject label to an existing LORIS candidate with the same CandID or PSCID.
    """

    cand_id = try_parse_int(subject_label)
    if cand_id is not None:
        return BidsCandidateConfig(cand_id=cand_id)

    return BidsCandidateConfig(psc_id=subject_label)


def get_default_bids_session_config(
    _env: Env,
    _candidate_config: BidsCandidateConfig,
    _subject_label: BidsSubjectLabel,
    session_label: BidsSessionLabel | None,
    _participant_row: BidsParticipantTsvRow | None,
    _session_row: BidsSessionTsvRow | None,
) -> BidsSessionConfig:
    """
    Map a BIDS session label to an existing LORIS session with the same visit label.
    """

    if session_label is None:
        raise BidsConfigError(
            "A BIDS configuration file is required to map a dataset without session labels."
        )

    return BidsSessionConfig(visit_label=session_label)


def _load_bids_config_module(path: Path) -> ModuleType:
    """
    Load and return a Python BIDS configuration module.
    """

    if path.suffix != '.py':
        raise BidsConfigError(f"BIDS configuration file '{path}' must be a Python file.")

    spec = importlib.util.spec_from_file_location(f'loris_bids_config_{path.stem}', path)
    if spec is None or spec.loader is None:
        raise BidsConfigError(f"Cannot load BIDS configuration file '{path}'.")

    module = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(module)
    except Exception as error:
        raise BidsConfigError(f"Cannot import BIDS configuration file '{path}': {error}") from error

    return module
