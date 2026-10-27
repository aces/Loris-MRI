"""Utilities for updating CTF `.res4` metadata.

The format constants below come from "CTF MEG File Formats", PN900-0088,
revision 1.3, pages 13 and 30-32:
https://megcore.nih.gov/images/a/a8/FileFormats.pdf
"""

from pathlib import Path

# PN900-0088 Table 2 defines an eight-byte MEG 4.2 resource-file identifier,
# followed by one 1,832-byte `meg41GeneralResRec` record.
RES4_HEADER = b'MEG42RS\x00'
GENERAL_RESOURCES_SIZE = 1832

# In the packed structures listed in PN900-0088, `meg41GeneralResRec` starts
# at byte 8 and contains `meg4FileSetup nfSetUp` at byte 1360. Within
# `nfSetUp`, the four fields before `nf_subject_id` occupy
# 32 + 256 + 32 + 32 bytes, placing its 32-byte CChar array at byte 1712.
SUBJECT_ID_OFFSET = 1712
SUBJECT_ID_SIZE = 32

MINIMUM_RES4_SIZE = len(RES4_HEADER) + GENERAL_RESOURCES_SIZE


def encode_subject(subject: str) -> bytes:
    """Encode a subject identifier as a 32-byte CTF `.res4` field."""

    try:
        encoded = subject.encode('latin-1')
    except UnicodeEncodeError as exc:
        raise ValueError(f"CTF res4 subject id must be Latin-1: {subject}") from exc
    if len(encoded) > SUBJECT_ID_SIZE:
        raise ValueError(f"CTF res4 subject id is limited to {SUBJECT_ID_SIZE} bytes: {subject}")
    return encoded + (b'\x00' * (SUBJECT_ID_SIZE - len(encoded)))


def replace_subject(ds_path: Path, subject: str) -> None:
    """Replace the subject identifier in every `.res4` file in a dataset."""

    padded = encode_subject(subject)
    res4_paths = sorted(ds_path.glob('*.res4'))

    # Validate every resource file before modifying any of them so a malformed
    # file cannot leave the dataset only partially updated.
    for file_path in res4_paths:
        _validate_file(file_path)

    for file_path in res4_paths:
        with file_path.open('r+b') as fid:
            fid.seek(SUBJECT_ID_OFFSET)
            fid.write(padded)


def _validate_file(file_path: Path) -> None:
    if file_path.stat().st_size < MINIMUM_RES4_SIZE:
        raise ValueError(
            f"CTF res4 file is shorter than the documented general resource "
            f"record ({MINIMUM_RES4_SIZE} bytes): {file_path}"
        )

    with file_path.open('rb') as fid:
        header = fid.read(len(RES4_HEADER))
    if header != RES4_HEADER:
        raise ValueError(f"Unsupported CTF res4 header in {file_path}: {header!r}; expected {RES4_HEADER!r}")
