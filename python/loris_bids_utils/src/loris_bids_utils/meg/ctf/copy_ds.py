"""
Copy CTF MEG .ds directories while updating their internal BIDS-derived metadata and CTF references.

This code is a Python port of the following Matlab code:
https://github.com/Moo-Marc/CtfMegBids/
"""

import re
import shutil
import warnings
from collections.abc import Iterable
from pathlib import Path

from loris_bids_utils.path import build_bids_modality_path, parse_bids_entities

KNOWN_DATASET_FILES = {
    "processing.cfg",
    "processing.cfg.bak",
    "ClassFile.cls",
    "ClassFile.cls.bak",
    "MarkerFile.mrk",
    "MarkerFile.mrk.bak",
    "default.de",
    "default.de.bak",
    "bad.segments",
    "bad.segments.bak",
    "BadChannels",
    "BadChannels.bak",
    "ChannelGroupSet.cfg",
    "ChannelGroupSet.cfg.bak",
    "VirtualChannels",
    "VirtualChannels.bak",
    "DigTrigChannelInfo.txt",
    "DigTrigChannelInfo.txt.bak",
    "params.dsc",
    "params.dsc.bak",
    "hz.ds",
    ".lock",
}


def copy_meg_ctf_ds(source_path: Path, destination_path: Path) -> list[Path]:
    """Copy a CTF ``.ds`` dataset and update internal CTF references.

    This is a Python port of the non-anonymizing behavior in
    ``Bids_ctf_rename_ds.m``, except it copies the source dataset instead of
    moving it. It renames files whose names start with the old dataset stem in
    the copy, removes empty ``.bak`` and ``.eeg`` files from the copy, updates
    ``.hist`` references, and rewrites the dataset path line in ``.cls`` and
    ``.mrk`` files.

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
    _validate_dataset_paths(source_path, destination_path)

    orig_name = _strip_ds_suffix(source_path.name)
    new_name = _strip_ds_suffix(destination_path.name)

    _copy_dataset(source_path, destination_path)
    _rename_dataset_files(destination_path, orig_name, new_name)
    unknown_files = _find_unknown_files(destination_path, new_name)

    if unknown_files:
        warnings.warn(f"Unknown files in {destination_path}", stacklevel=2)

    _delete_empty_files(destination_path.glob("*.bak"))
    _delete_empty_files(destination_path.glob("*.eeg"))
    _replace_text_in_first_file(
        destination_path, "*.hist", orig_name, new_name, "history"
    )
    _replace_dataset_path_line(
        destination_path, "*.cls", dataset_reference_path, "class"
    )
    _replace_dataset_path_line(
        destination_path, "*.mrk", dataset_reference_path, "marker"
    )
    _warn_if_old_name_remains(destination_path, orig_name)

    return unknown_files


def copy_bids_meg_ctf_ds(source_path: Path, destination_path: Path) -> list[Path]:
    """Copy a BIDS CTF ``.ds`` dataset and update BIDS-derived metadata."""

    _validate_dataset_paths(source_path, destination_path)

    orig_name = _strip_ds_suffix(source_path.name)
    new_name = _strip_ds_suffix(destination_path.name)
    relative_dataset_path = _relative_dataset_path(destination_path.name)
    subject_rename = _get_subject_rename(orig_name, new_name)
    if subject_rename is not None:
        _encode_res4_subject(subject_rename[1])

    unknown_files = _copy_meg_ctf_ds(
        source_path,
        destination_path,
        relative_dataset_path,
    )
    if subject_rename is not None:
        _replace_subject_metadata(destination_path, subject_rename[1])

    return unknown_files


def _validate_dataset_paths(source_path: Path, destination_path: Path):
    if not source_path.is_dir():
        raise FileNotFoundError(f"Dataset not found: {source_path}")
    if destination_path.suffix != ".ds":
        raise ValueError(
            f"Destination must be an explicit .ds dataset path: {destination_path}"
        )
    if source_path.resolve() == destination_path.resolve():
        raise ValueError("Destination must differ from the source dataset path.")


def _strip_ds_suffix(name: str) -> str:
    name_path = Path(name)
    if name_path.suffix == ".ds":
        return name_path.stem
    return name_path.name


def _relative_dataset_path(new_ds_name: str) -> Path:
    if new_ds_name == 'hz.ds':
        return Path(new_ds_name)

    if not new_ds_name.endswith('_meg.ds'):
        raise ValueError(
            f"New dataset name should follow BIDS specification: {new_ds_name}"
        )
    entities = parse_bids_entities(new_ds_name)
    if 'sub' not in entities or 'task' not in entities:
        raise ValueError(
            f"New dataset name should follow BIDS specification: {new_ds_name}"
        )
    return build_bids_modality_path(
        entities['sub'], entities.get('ses'), 'meg', new_ds_name
    )


def _copy_dataset(original_ds_path: Path, new_ds_path: Path):
    if original_ds_path == new_ds_path:
        raise ValueError("Destination must differ from the source dataset path.")

    if new_ds_path.exists():
        if not new_ds_path.is_dir():
            raise FileExistsError(
                f"Destination exists and is not a directory: {new_ds_path}"
            )
        for child_path in original_ds_path.iterdir():
            destination_child_path = new_ds_path / child_path.name
            if child_path.is_dir():
                shutil.copytree(
                    child_path, destination_child_path, dirs_exist_ok=True
                )
            else:
                shutil.copy2(child_path, destination_child_path)
    else:
        new_ds_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(original_ds_path, new_ds_path)


def _rename_dataset_files(ds_path: Path, orig_name: str, new_name: str):
    if orig_name == new_name:
        return

    for file_path in sorted(ds_path.glob(f"{orig_name}*")):
        renamed_path = file_path.with_name(
            file_path.name.replace(orig_name, new_name)
        )
        shutil.move(str(file_path), str(renamed_path))


def _find_unknown_files(ds_path: Path, new_name: str) -> list[Path]:
    expected_names = {
        candidate_path.name for candidate_path in ds_path.glob(f"{new_name}*")
    }
    expected_names.update(KNOWN_DATASET_FILES)

    unknown = [
        candidate_path.relative_to(ds_path)
        for candidate_path in ds_path.iterdir()
        if candidate_path.name not in expected_names
    ]
    return sorted(unknown)


def _delete_empty_files(files: Iterable[Path]):
    for file_path in files:
        if file_path.is_file() and file_path.stat().st_size == 0:
            file_path.unlink()


def _replace_text_in_first_file(ds_path: Path, pattern: str, old: str, new: str, file_kind: str):
    matches = sorted(ds_path.glob(pattern))
    if len(matches) > 1:
        warnings.warn(f"Multiple {file_kind} files found in {ds_path}", stacklevel=2)
        matches = matches[:1]
    if not matches:
        return

    file_path = matches[0]
    content = _read_text_lossless(file_path)
    file_path.write_text(content.replace(old, new), encoding="latin-1")


def _replace_dataset_path_line(ds_path: Path, pattern: str, relative_dataset_path: Path, file_kind: str):
    matches = sorted(ds_path.glob(pattern))
    if len(matches) > 1:
        warnings.warn(f"Multiple {file_kind} files found in {ds_path}", stacklevel=2)
        matches = matches[:1]
    if not matches:
        return

    file_path = matches[0]
    content = _read_text_lossless(file_path)
    line_breaks = [match.start() for match in re.finditer(r"\n", content)]
    if len(line_breaks) < 2:
        warnings.warn(
            f"Could not update dataset path in {file_path}: expected at least 2 lines",
            stacklevel=2,
        )
        return

    start = line_breaks[0] + 1
    end = line_breaks[1]
    old_path = content[start:end]
    updated = content.replace(old_path, str(relative_dataset_path))
    file_path.write_text(updated, encoding="latin-1")


def _get_subject_rename(orig_name: str, new_name: str) -> tuple[str, str] | None:
    orig_name_with_ext = f"{orig_name}.ds"
    new_name_with_ext = f"{new_name}.ds"
    if not orig_name.endswith("_meg") or not new_name.endswith("_meg"):
        return None
    try:
        orig_info = parse_bids_entities(orig_name_with_ext)
        new_info = parse_bids_entities(new_name_with_ext)
    except ValueError:
        return None

    old_subject_label = orig_info.get("sub")
    new_subject_label = new_info.get("sub")
    if (
        old_subject_label is None
        or new_subject_label is None
        or old_subject_label == new_subject_label
    ):
        return None

    return f"sub-{old_subject_label}", f"sub-{new_subject_label}"


def _replace_subject_metadata(ds_path: Path, new_subject: str):
    _replace_res4_subject(ds_path, new_subject)
    _replace_infods_patient_id(ds_path, new_subject)


def _encode_res4_subject(subject: str) -> bytes:
    try:
        encoded = subject.encode("latin-1")
    except UnicodeEncodeError as exc:
        raise ValueError(f"CTF res4 subject id must be Latin-1: {subject}") from exc
    if len(encoded) > 32:
        raise ValueError(f"CTF res4 subject id is limited to 32 bytes: {subject}")
    return encoded + (b"\x00" * (32 - len(encoded)))


def _replace_res4_subject(ds_path: Path, subject: str):
    padded = _encode_res4_subject(subject)

    for file_path in sorted(ds_path.glob("*.res4")):
        with file_path.open("r+b") as fid:
            fid.seek(1712)
            fid.write(padded)


def _replace_infods_patient_id(ds_path: Path, new_subject: str):
    replacements = {"_PATIENT_ID": new_subject}
    for file_path in sorted(ds_path.glob("*.infods")):
        updated = _replace_cpersist_strings(file_path.read_bytes(), replacements)
        file_path.write_bytes(updated)


def _replace_cpersist_strings(content: bytes, replacements: dict[str, str]) -> bytes:
    start_value = int.from_bytes(b"WS1_", byteorder="big", signed=True)
    end_tag = "EndOfParameters"
    out = bytearray()
    pos = 0

    while pos + 4 <= len(content):
        tag_start = pos
        tag_length = int.from_bytes(content[pos : pos + 4], "big", signed=True)
        pos += 4

        if tag_length == start_value:
            out.extend(content[tag_start:pos])
            continue
        if tag_length <= 0 or pos + tag_length > len(content):
            out.extend(content[tag_start:])
            return bytes(out)

        tag_name = content[pos : pos + tag_length].decode("latin-1")
        pos += tag_length
        out.extend(content[tag_start:pos])

        if tag_name == end_tag:
            continue
        if pos + 4 > len(content):
            out.extend(content[pos:])
            return bytes(out)

        tag_type = int.from_bytes(content[pos : pos + 4], "big", signed=True)
        out.extend(content[pos : pos + 4])
        pos += 4

        if tag_type == 10:
            if pos + 4 > len(content):
                out.extend(content[pos:])
                return bytes(out)
            string_length = int.from_bytes(content[pos : pos + 4], "big", signed=True)
            value_start = pos + 4
            value_end = value_start + string_length
            if string_length < 0 or value_end > len(content):
                out.extend(content[pos:])
                return bytes(out)

            value = content[value_start:value_end].decode("latin-1")
            if tag_name in replacements:
                value = replacements[tag_name]
            encoded = value.encode("latin-1")
            out.extend(len(encoded).to_bytes(4, "big", signed=True))
            out.extend(encoded)
            pos = value_end
            continue

        value_end = _cpersist_value_end(content, pos, tag_type, tag_name)
        if value_end is None:
            out.extend(content[pos:])
            return bytes(out)
        out.extend(content[pos:value_end])
        pos = value_end

    out.extend(content[pos:])
    return bytes(out)


def _cpersist_value_end(content: bytes, pos: int, tag_type: int, tag_name: str) -> int | None:
    fixed_widths = {
        2: 0,
        4: 8,
        5: 4,
        6: 2,
        7: 2,
        8: 1,
        9: 32,
        14: 4,
        15: 4,
        16: 4,
        17: 4,
    }
    if tag_type == 1:
        return pos + 4 if tag_name == "DatasetFiles" else pos
    if tag_type in fixed_widths:
        return pos + fixed_widths[tag_type]
    if tag_type == 3:
        if pos + 4 > len(content):
            return None
        byte_count = int.from_bytes(content[pos : pos + 4], "big", signed=True)
        return pos + 4 + byte_count
    if tag_type == 11:
        if pos + 4 > len(content):
            return None
        count = int.from_bytes(content[pos : pos + 4], "big", signed=True)
        value_pos = pos + 4
        for _ in range(count):
            if value_pos + 4 > len(content):
                return None
            string_length = int.from_bytes(
                content[value_pos : value_pos + 4],
                "big",
                signed=True,
            )
            value_pos += 4 + string_length
        return value_pos
    if tag_type == 12:
        if pos + 4 > len(content):
            return None
        count = int.from_bytes(content[pos : pos + 4], "big", signed=True)
        return pos + 4 + (32 * count)
    if tag_type == 13:
        if pos + 4 > len(content):
            return None
        count = int.from_bytes(content[pos : pos + 4], "big", signed=True)
        return pos + 4 + (4 * count)
    return None


def _warn_if_old_name_remains(ds_path: Path, orig_name: str):
    if orig_name == _strip_ds_suffix(ds_path.name):
        return

    old_name = orig_name.encode("latin-1")
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
    chunk_size = 1024 * 1024
    overlap = max(len(needle) - 1, 0)
    previous = b""

    with file_path.open("rb") as fid:
        while True:
            chunk = fid.read(chunk_size)
            if not chunk:
                return False
            data = previous + chunk
            if needle in data:
                return True
            previous = data[-overlap:] if overlap else b""


def _read_text_lossless(file_path: Path) -> str:
    return file_path.read_text(encoding="latin-1")
