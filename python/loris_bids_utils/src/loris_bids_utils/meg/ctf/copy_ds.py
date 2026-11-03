"""
Copy CTF MEG .ds directories while updating their internal BIDS-derived metadata and CTF references.

This code is a Python port of `Bids_ctf_rename_ds.m` from CtfMegBids at
commit `f550ecf776733f92d0855e294309b2a1e93a262d`:
https://github.com/Moo-Marc/CtfMegBids/blob/f550ecf776733f92d0855e294309b2a1e93a262d/Bids_ctf_rename_ds.m
"""

import re
import shutil
import warnings
from collections.abc import Iterable
from pathlib import Path

from loris_bids_utils.meg.ctf import cpersist, res4
from loris_bids_utils.path import build_bids_modality_path, parse_bids_entities

KNOWN_DATASET_FILES = {
    'processing.cfg',
    'processing.cfg.bak',
    'ClassFile.cls',
    'ClassFile.cls.bak',
    'MarkerFile.mrk',
    'MarkerFile.mrk.bak',
    'default.de',
    'default.de.bak',
    'bad.segments',
    'bad.segments.bak',
    'BadChannels',
    'BadChannels.bak',
    'ChannelGroupSet.cfg',
    'ChannelGroupSet.cfg.bak',
    'VirtualChannels',
    'VirtualChannels.bak',
    'DigTrigChannelInfo.txt',
    'DigTrigChannelInfo.txt.bak',
    'params.dsc',
    'params.dsc.bak',
    'hz.ds',
    '.lock',
}


def copy_meg_ctf_ds(source_path: Path, destination_path: Path) -> list[Path]:
    """Copy a CTF `.ds` dataset and update internal CTF references.

    This is a Python port of the non-anonymizing behavior in
    `Bids_ctf_rename_ds.m`, except it copies the source dataset instead of
    moving it. It renames files whose names start with the old dataset stem in
    the copy, removes empty `.bak` and `.eeg` files from the copy, updates
    `.hist` references, and rewrites the dataset path line in `.cls` and
    `.mrk` files.

    Args:
        source_path: Path to the source CTF dataset directory.
        destination_path: Exact path of the destination CTF dataset directory.

    Returns:
        Unknown files found after the rename, using paths relative to the new
        dataset directory.
    """

    return _copy_meg_ctf_ds(
        source_path,
        destination_path,
        Path(destination_path.name),
    )


def _copy_meg_ctf_ds(source_path: Path, destination_path: Path, dataset_reference_path: Path) -> list[Path]:
    """Copy one dataset and update references derived from its directory name."""

    _validate_dataset_paths(source_path, destination_path)

    orig_name = _strip_ds_suffix(source_path.name)
    new_name = _strip_ds_suffix(destination_path.name)

    _copy_dataset(source_path, destination_path)
    _rename_dataset_files(destination_path, orig_name, new_name)
    unknown_files = _find_unknown_files(destination_path, new_name)

    if unknown_files:
        warnings.warn(f"Unknown files in {destination_path}", stacklevel=2)

    _delete_empty_files(destination_path.glob('*.bak'))
    _delete_empty_files(destination_path.glob('*.eeg'))
    _replace_text_in_first_file(destination_path, '*.hist', orig_name, new_name, 'history')
    _replace_dataset_path_line(destination_path, '*.cls', dataset_reference_path, 'class')
    _replace_dataset_path_line(destination_path, '*.mrk', dataset_reference_path, 'marker')
    _warn_if_old_name_remains(destination_path, orig_name)

    return unknown_files


def copy_bids_meg_ctf_ds(source_path: Path, destination_path: Path) -> list[Path]:
    """Copy a BIDS CTF `.ds` dataset and update BIDS-derived metadata."""

    _validate_dataset_paths(source_path, destination_path)

    orig_name = _strip_ds_suffix(source_path.name)
    new_name = _strip_ds_suffix(destination_path.name)
    relative_dataset_path = _relative_dataset_path(destination_path.name)
    new_subject = _get_new_subject(orig_name, new_name)
    if new_subject is not None:
        res4.encode_subject(new_subject)

    unknown_files = _copy_meg_ctf_ds(
        source_path,
        destination_path,
        relative_dataset_path,
    )
    if new_subject is not None:
        _replace_subject_metadata(destination_path, new_subject)

    return unknown_files


def _validate_dataset_paths(source_path: Path, destination_path: Path):
    """Validate source and destination paths before copying any files."""

    if not source_path.is_dir():
        raise FileNotFoundError(f"Dataset not found: {source_path}")
    if destination_path.suffix != '.ds':
        raise ValueError(f"Destination must be an explicit .ds dataset path: {destination_path}")
    resolved_source = source_path.resolve()
    resolved_destination = destination_path.resolve()
    if resolved_source == resolved_destination:
        raise ValueError("Destination must differ from the source dataset path.")
    if resolved_destination.is_relative_to(resolved_source):
        raise ValueError("Destination must not be inside the source dataset path.")
    if destination_path.exists():
        if not destination_path.is_dir():
            raise FileExistsError(f"Destination exists and is not a directory: {destination_path}")
        if any(destination_path.iterdir()):
            raise FileExistsError(f"Destination directory is not empty: {destination_path}")


def _strip_ds_suffix(name: str) -> str:
    """Return a dataset name without its final `.ds` suffix."""

    name_path = Path(name)
    if name_path.suffix == '.ds':
        return name_path.stem
    return name_path.name


def _relative_dataset_path(new_ds_name: str) -> Path:
    """Build the path stored in CTF text metadata for a BIDS dataset."""

    if new_ds_name == 'hz.ds':
        return Path(new_ds_name)

    if not new_ds_name.endswith('_meg.ds'):
        raise ValueError(f"New dataset name should follow BIDS specification: {new_ds_name}")
    entities = parse_bids_entities(new_ds_name)
    if 'sub' not in entities or 'task' not in entities:
        raise ValueError(f"New dataset name should follow BIDS specification: {new_ds_name}")
    return build_bids_modality_path(entities['sub'], entities.get('ses'), 'meg', new_ds_name)


def _copy_dataset(original_ds_path: Path, new_ds_path: Path):
    """Copy a validated dataset into a new or empty destination directory."""

    if new_ds_path.exists():
        for child_path in original_ds_path.iterdir():
            destination_child_path = new_ds_path / child_path.name
            if child_path.is_dir():
                shutil.copytree(child_path, destination_child_path, dirs_exist_ok=True)
            else:
                shutil.copy2(child_path, destination_child_path)
    else:
        new_ds_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(original_ds_path, new_ds_path)


def _rename_dataset_files(ds_path: Path, orig_name: str, new_name: str):
    """Rename files whose names begin with the source dataset name."""

    if orig_name == new_name:
        return

    for file_path in sorted(ds_path.glob(f'{orig_name}*')):
        renamed_path = file_path.with_name(new_name + file_path.name[len(orig_name) :])
        shutil.move(str(file_path), str(renamed_path))


def _find_unknown_files(ds_path: Path, new_name: str) -> list[Path]:
    """Return copied entries not recognized as standard dataset files."""

    expected_names = {candidate_path.name for candidate_path in ds_path.glob(f'{new_name}*')}
    expected_names.update(KNOWN_DATASET_FILES)

    unknown = [
        candidate_path.relative_to(ds_path)
        for candidate_path in ds_path.iterdir()
        if candidate_path.name not in expected_names
    ]
    return sorted(unknown)


def _delete_empty_files(files: Iterable[Path]):
    """Delete zero-length files from a collection of candidate paths."""

    for file_path in files:
        if file_path.is_file() and file_path.stat().st_size == 0:
            file_path.unlink()


def _replace_text_in_first_file(ds_path: Path, pattern: str, old: str, new: str, file_kind: str):
    """Replace text in the first matching file and warn about extra matches."""

    matches = sorted(ds_path.glob(pattern))
    if len(matches) > 1:
        warnings.warn(f"Multiple {file_kind} files found in {ds_path}", stacklevel=2)
        matches = matches[:1]
    if not matches:
        return

    file_path = matches[0]
    content = _read_text_lossless(file_path)
    _write_text_lossless(file_path, content.replace(old, new))


def _replace_dataset_path_line(ds_path: Path, pattern: str, relative_dataset_path: Path, file_kind: str):
    """Replace only the dataset-path line in the first matching text file."""

    matches = sorted(ds_path.glob(pattern))
    if len(matches) > 1:
        warnings.warn(f"Multiple {file_kind} files found in {ds_path}", stacklevel=2)
        matches = matches[:1]
    if not matches:
        return

    file_path = matches[0]
    content = _read_text_lossless(file_path)
    line_breaks = [match.start() for match in re.finditer(r'\n', content)]
    if len(line_breaks) < 2:
        warnings.warn(
            f"Could not update dataset path in {file_path}: expected at least 2 lines",
            stacklevel=2,
        )
        return

    start = line_breaks[0] + 1
    end = line_breaks[1]
    carriage_return = '\r' if content[end - 1 : end] == '\r' else ''
    updated = content[:start] + str(relative_dataset_path) + carriage_return + content[end:]
    _write_text_lossless(file_path, updated)


def _get_new_subject(orig_name: str, new_name: str) -> str | None:
    """Return the destination subject when a BIDS dataset changes subject."""

    orig_name_with_ext = f'{orig_name}.ds'
    new_name_with_ext = f'{new_name}.ds'
    if not orig_name.endswith('_meg') or not new_name.endswith('_meg'):
        return None
    try:
        orig_info = parse_bids_entities(orig_name_with_ext)
        new_info = parse_bids_entities(new_name_with_ext)
    except ValueError:
        return None

    old_subject_label = orig_info.get('sub')
    new_subject_label = new_info.get('sub')
    if old_subject_label is None or new_subject_label is None or old_subject_label == new_subject_label:
        return None

    return f'sub-{new_subject_label}'


def _replace_subject_metadata(ds_path: Path, new_subject: str):
    """Update subject identifiers in the dataset's binary metadata files."""

    res4.replace_subject(ds_path, new_subject)
    _replace_infods_patient_id(ds_path, new_subject)


def _replace_infods_patient_id(ds_path: Path, new_subject: str):
    """Update the patient identifier in every CPersist `.infods` file."""

    replacements = {'_PATIENT_ID': new_subject}
    for file_path in sorted(ds_path.glob('*.infods')):
        updated = cpersist.replace_strings(file_path.read_bytes(), replacements)
        file_path.write_bytes(updated)


def _warn_if_old_name_remains(ds_path: Path, orig_name: str):
    """Warn when copied files still contain the source dataset name."""

    if orig_name == _strip_ds_suffix(ds_path.name):
        return

    old_name = orig_name.encode('latin-1')
    matching_paths = [
        candidate_path.relative_to(ds_path)
        for candidate_path in ds_path.iterdir()
        if candidate_path.is_file() and _file_contains(candidate_path, old_name)
    ]
    if matching_paths:
        warnings.warn(
            "Old dataset name still appears in copied files: "
            + ", ".join(str(match_path) for match_path in sorted(matching_paths)),
            stacklevel=2,
        )


def _file_contains(file_path: Path, needle: bytes) -> bool:
    """Search a file for bytes without loading the whole file into memory."""

    chunk_size = 1024 * 1024
    overlap = max(len(needle) - 1, 0)
    previous = b''

    with file_path.open('rb') as fid:
        while True:
            chunk = fid.read(chunk_size)
            if not chunk:
                return False
            data = previous + chunk
            if needle in data:
                return True
            previous = data[-overlap:] if overlap else b''


def _read_text_lossless(file_path: Path) -> str:
    """Read CTF text while preserving every byte through Latin-1."""

    return file_path.read_bytes().decode('latin-1')


def _write_text_lossless(file_path: Path, content: str):
    """Write CTF text without translating newline bytes."""

    file_path.write_bytes(content.encode('latin-1'))
