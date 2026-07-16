import struct
import warnings
from pathlib import Path

import pytest

from loris_bids_utils.meg.ctf.copy_ds import copy_bids_meg_ctf_ds, copy_meg_ctf_ds

from ._synthetic import document, patient_info, resource_file


def _snapshot(directory: Path) -> dict[Path, bytes]:
    return {path.relative_to(directory): path.read_bytes() for path in directory.rglob('*') if path.is_file()}


def _marker_file(dataset: str, newline: bytes) -> bytes:
    # PN900-0088 pp. 57-60. A comment containing the old name is event metadata,
    # not a dataset reference, and must survive relocation verbatim.
    lines = [
        b'PATH OF DATASET:', b'/original/' + dataset.encode('ascii'),
        b'NUMBER OF MARKERS:', b'1', b'CLASSGROUPID:', b'3',
        b'NAME:', b'stimulus', b'COMMENT:', b'recorded in ' + dataset.encode('ascii'),
        b'COLOR:', b'green', b'EDITABLE:', b'Yes', b'CLASSID:', b'1',
        b'NUMBER OF SAMPLES:', b'2', b'LIST OF SAMPLES:',
        b'TRIAL NUMBER\tTIME FROM SYNC POINT (in seconds)', b'+0\t-0.125', b'+1\t+0.250',
    ]
    return newline.join(lines) + newline


def _class_file(dataset: str, newline: bytes) -> bytes:
    # PN900-0088 pp. 61-64. Trial indices and class labels are unchanged by copy.
    lines = [
        b'PATH OF DATASET:', b'/original/' + dataset.encode('ascii'),
        b'NUMBER OF CLASSES:', b'1', b'CLASSGROUPID:', b'3',
        b'NAME:', b'Bad-Blink', b'COMMENT:', b'caf\xe9', b'COLOR:', b'red',
        b'EDITABLE:', b'Yes', b'CLASSID:', b'1', b'NUMBER OF TRIALS:', b'2',
        b'LIST OF TRIALS:', b'TRIAL NUMBER', b'+0', b'+1',
    ]
    return newline.join(lines) + newline


@pytest.mark.parametrize('newline', [b'\n', b'\r\n'], ids=['LF', 'CRLF'])
@pytest.mark.parametrize(('new_name', 'relative_path', 'subject'), [
    ('sub-new_task-rest_meg', 'sub-new/meg/sub-new_task-rest_meg.ds', b'sub-new'),
    ('sub-longsubject_task-rest_meg', 'sub-longsubject/meg/sub-longsubject_task-rest_meg.ds', b'sub-longsubject'),
    ('sub-new_ses-V1_task-rest_run-02_meg',
     'sub-new/ses-V1/meg/sub-new_ses-V1_task-rest_run-02_meg.ds', b'sub-new'),
    ('sub-old_ses-V1_task-rest_meg', 'sub-old/ses-V1/meg/sub-old_ses-V1_task-rest_meg.ds', b'sub-old'),
])
def test_bids_copy_preserves_ctf_records_and_updates_references(
    tmp_path: Path, newline: bytes, new_name: str, relative_path: str, subject: bytes,
):
    old_name = 'sub-old_task-rest_meg'
    source = tmp_path / f'{old_name}.ds'
    destination = tmp_path / 'arbitrary-output-parent' / f'{new_name}.ds'
    source.mkdir()
    files = {
        f'{old_name}.res4': resource_file(b'sub-old'),
        f'{old_name}.infods': patient_info(b'sub-old'),
        f'{old_name}.acq': document(),
        f'{old_name}.hc': b'measured nasion coil position relative to dewar (cm):\nx = 1\ny = 2\nz = 3\n',
        f'{old_name}.eeg': b'1\tCz\t0.0\t0.0\t10.0\n',
        'MarkerFile.mrk': _marker_file(source.name, newline),
        'ClassFile.cls': _class_file(source.name, newline),
        'BadChannels': b'MLC11\n',
        'bad.segments': b'0\t0.125\t0.250\n',
        'VirtualChannels': b'Version: 1.0\n',
    }
    # PN900-0088 p. 11: MEG41CP header and big-endian signed int32 samples.
    # Brainstorm ctf_get_files.m: continuation files use .1_meg4, .2_meg4, ...
    for suffix in ['.meg4', '.1_meg4', '.2_meg4']:
        files[old_name + suffix] = b'MEG41CP\0' + struct.pack('>iiii', -2147483648, -1, 0, 2147483647)
    for name, content in files.items():
        (source / name).write_bytes(content)
    before = _snapshot(source)

    # The intentionally retained historical name in the marker comment warrants
    # a warning, but no modification of event metadata.
    with pytest.warns(UserWarning, match='Old dataset name still appears'):
        unknown = copy_bids_meg_ctf_ds(source, destination)

    assert unknown == []
    expected = {
        Path(name.replace(old_name, new_name, 1) if name.startswith(old_name) else name): content
        for name, content in files.items()
    }
    expected[Path(f'{new_name}.res4')] = resource_file(subject)
    # Build expected infods by replacing only the tagged patient ID. The same
    # old identifier in _DATASET_COMMENTS must remain unchanged.
    info = patient_info(b'sub-old')
    old_id = b'\x00\x00\x00\x0b_PATIENT_ID\x00\x00\x00\x0a\x00\x00\x00\x07sub-old'
    new_id = b'\x00\x00\x00\x0b_PATIENT_ID\x00\x00\x00\x0a' + struct.pack('>i', len(subject)) + subject
    expected[Path(f'{new_name}.infods')] = info.replace(old_id, new_id)
    for name in ['MarkerFile.mrk', 'ClassFile.cls']:
        header, _, body = files[name].split(newline, 2)
        expected[Path(name)] = header + newline + relative_path.encode('ascii') + newline + body
    assert _snapshot(destination) == expected
    assert _snapshot(source) == before


def test_generic_copy_preserves_subject_metadata_and_nested_head_localization(tmp_path: Path):
    source = tmp_path / 'sub-old_task-rest_meg.ds'
    destination = tmp_path / 'sub-new_task-rest_meg.ds'
    source.mkdir()
    (source / 'sub-old_task-rest_meg.res4').write_bytes(resource_file(b'sub-old'))
    (source / 'sub-old_task-rest_meg.infods').write_bytes(patient_info(b'sub-old'))
    (source / 'ClassFile.cls').write_bytes(_class_file(source.name, b'\n'))
    (source / 'hz.ds').mkdir()
    (source / 'hz.ds/hz.meg4').write_bytes(b'MEG41CP\0' + struct.pack('>i', 123))
    before = _snapshot(source)

    assert copy_meg_ctf_ds(source, destination) == []

    assert (destination / 'sub-new_task-rest_meg.res4').read_bytes() == resource_file(b'sub-old')
    assert (destination / 'sub-new_task-rest_meg.infods').read_bytes() == patient_info(b'sub-old')
    assert (destination / 'ClassFile.cls').read_bytes().splitlines()[1] == destination.name.encode('ascii')
    assert _snapshot(destination / 'hz.ds') == _snapshot(source / 'hz.ds')
    assert _snapshot(source) == before


def test_sample_bytes_are_not_rewritten_even_if_they_contain_old_name(tmp_path: Path):
    source = tmp_path / 'old.ds'
    destination = tmp_path / 'new.ds'
    source.mkdir()
    # A coincidental ASCII match in binary samples is not a reference.
    samples = b'MEG41CP\0old\x00'
    (source / 'old.meg4').write_bytes(samples)

    with pytest.warns(UserWarning, match='Old dataset name still appears'):
        copy_meg_ctf_ds(source, destination)

    assert (destination / 'new.meg4').read_bytes() == samples
    assert (source / 'old.meg4').read_bytes() == samples


def test_copy_preserves_unknown_files_and_reports_them(tmp_path: Path):
    source = tmp_path / 'old.ds'
    source.mkdir()
    (source / 'notes.bin').write_bytes(bytes(range(256)))
    destination = tmp_path / 'new.ds'

    with pytest.warns(UserWarning, match='Unknown files'):
        unknown = copy_meg_ctf_ds(source, destination)

    assert unknown == [Path('notes.bin')]
    assert _snapshot(destination) == _snapshot(source)


def test_copy_accepts_existing_empty_destination(tmp_path: Path):
    source = tmp_path / 'old.ds'
    source.mkdir()
    (source / 'old.acq').write_bytes(document())
    destination = tmp_path / 'new.ds'
    destination.mkdir()

    assert copy_meg_ctf_ds(source, destination) == []
    assert (destination / 'new.acq').read_bytes() == document()


@pytest.mark.parametrize('kind', ['same', 'nested', 'symlink', 'nonempty', 'file', 'suffix'])
def test_unsafe_destinations_are_rejected_without_modifying_source(tmp_path: Path, kind: str):
    source = tmp_path / 'source.ds'
    source.mkdir()
    (source / 'source.meg4').write_bytes(b'MEG41CP\0')
    destination = tmp_path / 'destination.ds'
    if kind == 'same':
        destination = source
    elif kind == 'nested':
        destination = source / 'nested.ds'
    elif kind == 'symlink':
        destination.symlink_to(source, target_is_directory=True)
    elif kind == 'nonempty':
        destination.mkdir()
        (destination / 'precious.txt').write_bytes(b'preserve me')
    elif kind == 'file':
        destination.write_bytes(b'preserve me')
    elif kind == 'suffix':
        destination = tmp_path / 'destination'
    before = _snapshot(tmp_path)

    with pytest.raises((ValueError, FileExistsError)):
        copy_meg_ctf_ds(source, destination)

    assert _snapshot(tmp_path) == before


def test_missing_source_does_not_create_destination(tmp_path: Path):
    destination = tmp_path / 'new.ds'
    with pytest.raises(FileNotFoundError):
        copy_meg_ctf_ds(tmp_path / 'missing.ds', destination)
    assert not destination.exists()


@pytest.mark.parametrize('name', ['plain.ds', 'sub-new_meg.ds', 'task-rest_meg.ds', f'sub-{"x" * 29}_task-rest_meg.ds'])
def test_invalid_bids_destination_is_rejected_before_copying(tmp_path: Path, name: str):
    source = tmp_path / 'sub-old_task-rest_meg.ds'
    source.mkdir()
    (source / 'sub-old_task-rest_meg.res4').write_bytes(resource_file(b'sub-old'))
    destination = tmp_path / name
    before = _snapshot(source)

    with pytest.raises(ValueError):
        copy_bids_meg_ctf_ds(source, destination)

    assert not destination.exists()
    assert _snapshot(source) == before


def test_copy_preserves_history_without_dataset_name(tmp_path: Path):
    source = tmp_path / 'old.ds'
    destination = tmp_path / 'new.ds'
    source.mkdir()
    history = b'Collection started\r\nNo dataset reference here\r\n'
    (source / 'old.hist').write_bytes(history)

    with warnings.catch_warnings():
        warnings.simplefilter('error')
        copy_meg_ctf_ds(source, destination)

    assert (destination / 'new.hist').read_bytes() == history


def test_copy_housekeeping_preserves_nonempty_eeg_and_backup_files(tmp_path: Path):
    # Application policy, not a requirement of the CTF file format.
    source = tmp_path / 'old.ds'
    destination = tmp_path / 'new.ds'
    source.mkdir()
    files = {
        'old.eeg': b'1\tCz\t0\t0\t10\n',
        'old.res4.bak': b'nonempty backup',
        'processing.cfg.bak': b'',
        'old.unused.eeg': b'',
        'old.hist': b'opened old.ds\r\n',
    }
    for name, content in files.items():
        (source / name).write_bytes(content)
    before = _snapshot(source)

    assert copy_meg_ctf_ds(source, destination) == []

    assert _snapshot(destination) == {
        Path('new.eeg'): files['old.eeg'],
        Path('new.res4.bak'): files['old.res4.bak'],
        Path('new.hist'): b'opened new.ds\r\n',
    }
    assert _snapshot(source) == before
