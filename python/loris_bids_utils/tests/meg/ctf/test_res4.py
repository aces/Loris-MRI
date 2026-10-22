from pathlib import Path

import pytest

from loris_bids_utils.meg.ctf.res4 import encode_subject, replace_subject

from ._synthetic import resource_file


@pytest.mark.parametrize('subject', ['', 'sub-123', 'sub-Andr\xe9', 'x' * 32])
def test_encode_subject_fills_exactly_32_bytes(subject: str):
    assert encode_subject(subject) == subject.encode('latin-1').ljust(32, b'\0')


@pytest.mark.parametrize('subject', ['x' * 33, '\N{SNOWMAN}'])
def test_encode_subject_rejects_unrepresentable_identifiers(subject: str):
    with pytest.raises(ValueError):
        encode_subject(subject)


@pytest.mark.parametrize('subject', ['sub-new', '', 'x' * 32])
def test_replace_subject_changes_only_the_subject_field(tmp_path: Path, subject: str):
    # A full old field detects stale bytes when replacing with a shorter value.
    original = resource_file(b'x' * 32)
    path = tmp_path / 'recording.res4'
    path.write_bytes(original)

    replace_subject(tmp_path, subject)

    # This literal offset follows from the independently assembled field order,
    # not imports of SUBJECT_ID_OFFSET/SIZE or a production encoder as oracle.
    assert original[1712:1744] == b'x' * 32
    assert path.read_bytes() == resource_file(subject.encode('latin-1'))
    assert len(path.read_bytes()) == len(original)


@pytest.mark.parametrize('size', [0, 7, 8, 1712, 1743, 1839])
def test_replace_subject_rejects_incomplete_general_resources(tmp_path: Path, size: int):
    path = tmp_path / 'recording.res4'
    original = resource_file(b'old')[:size]
    path.write_bytes(original)

    with pytest.raises(ValueError):
        replace_subject(tmp_path, 'sub-new')

    assert path.read_bytes() == original


def test_replace_subject_rejects_unsupported_header(tmp_path: Path):
    path = tmp_path / 'recording.res4'
    original = b'NOTRES4\0' + resource_file(b'old')[8:]
    path.write_bytes(original)

    with pytest.raises(ValueError, match='Unsupported CTF res4 header'):
        replace_subject(tmp_path, 'sub-new')

    assert path.read_bytes() == original


def test_replace_subject_validates_all_files_before_writing(tmp_path: Path):
    valid = tmp_path / 'a.res4'
    invalid = tmp_path / 'b.res4'
    original = resource_file(b'old')
    valid.write_bytes(original)
    invalid.write_bytes(b'broken')

    with pytest.raises(ValueError):
        replace_subject(tmp_path, 'sub-new')

    assert valid.read_bytes() == original
    assert invalid.read_bytes() == b'broken'


def test_replace_subject_updates_each_resource_file(tmp_path: Path):
    for name in ['a.res4', 'b.res4']:
        (tmp_path / name).write_bytes(resource_file(b'old'))

    replace_subject(tmp_path, 'sub-new')

    for name in ['a.res4', 'b.res4']:
        assert (tmp_path / name).read_bytes() == resource_file(b'sub-new')
