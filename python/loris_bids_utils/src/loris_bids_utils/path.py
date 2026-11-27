"""Small, dependency-free helpers for BIDS names and relative paths."""

from pathlib import Path

from loris_utils.iter import filter_non_none
from loris_utils.path import remove_name_extension
from loris_utils.sort import sort_dict_by_key_order

# The standard order in which BIDS entities should appear in a file name.
# https://bids-specification.readthedocs.io/en/stable/appendices/entity-table.html
BIDS_ENTITY_ORDER = [
    'sub',        # Subject
    'ses',        # Session
    'task',       # Task
    'acq',        # Acquisition
    'ce',         # Contrast Enhancing Agent
    'rec',        # Reconstruction
    'dir',        # Phase Encoding Direction
    'run',        # Run
    'mod',        # Corresponding Modality
    'echo',       # Echo
    'flip',       # Flip Angle
    'inv',        # Inversion Time
    'mt',         # Magnetization Transfer
    'part',       # Part
    'space',      # Coordinate System Space
    'split',      # Split
    'recording',  # Recording
]


def parse_bids_entities(name: str) -> dict[str, str]:
    """
    Parse the entities from a BIDS file name. This function assumes the provided BIDS file name is
    formatted correctly.
    """

    stem = remove_name_extension(name)

    parts = stem.split('_')

    entities: dict[str, str] = {}

    # Ignore the BIDS suffix.
    for pair in parts[:-1]:
        key, value = pair.split('-', 1)
        entities[key] = value

    return entities


def build_bids_file_name(entities: dict[str, str], suffix: str, extension: str) -> str:
    """
    Build a BIDS file name from its entities, suffix, and extension.
    """

    # Sort the BIDS entities according to the BIDS entity order.
    ordered_entities = sort_dict_by_key_order(entities, BIDS_ENTITY_ORDER)

    # Build the BIDS key label pairs from the BIDS entities.
    prefix = '_'.join(f'{key}-{label}' for key, label in ordered_entities.items())

    # Build the final BIDS file name.
    return f'{prefix}_{suffix}.{extension}'


def build_bids_subject_path(subject: str, file_name: str) -> Path:
    """
    Build a BIDS path for a file at the subject level.
    """

    return Path(f'sub-{subject}', file_name)


def build_bids_session_path(subject: str, session: str | None, file_name: str) -> Path:
    """
    Build a BIDS path for a file at the session level.
    """

    return Path(*filter_non_none([
        f'sub-{subject}',
        f'ses-{session}' if session is not None else None,
        file_name,
    ]))


def build_bids_modality_path(subject: str, session: str | None, data_type: str, file_name: str) -> Path:
    """
    Build a BIDS path for a file at the modality level.
    """

    return Path(*filter_non_none([
        f'sub-{subject}',
        f'ses-{session}' if session is not None else None,
        data_type,
        file_name,
    ]))
