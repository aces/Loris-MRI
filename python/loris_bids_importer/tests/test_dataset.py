from pathlib import Path

import pytest
from lib.db.models.bids_dataset import DbBidsDataset
from lib.db.models.bids_file import DbBidsFile
from lib.env import Env
from loris_utils.crypto import compute_file_blake2b_hash
from sqlalchemy import func, select

from loris_bids_importer.copy_files import copy_bids_static_files
from loris_bids_importer.dataset import get_or_create_loris_bids_file
from loris_bids_importer.importer import BidsImporter, BidsImporterArgs


@pytest.mark.parametrize(('name', 'suffix', 'extension', 'has_suffix'), [
    ('sub-01_T1w.nii.gz', 'T1w', 'nii.gz', True),
    ('sub-01_T1w.json', 'T1w', 'json', True),
    ('sub-01_task-rest_events.tsv', 'events', 'tsv', True),
    ('sub-01_task-rest_physio.tsv.gz', 'physio', 'tsv.gz', True),
    ('sub-01_task-rest_eeg.vhdr', 'eeg', 'vhdr', True),
    ('sub-01_task-rest_eeg.eeg', 'eeg', 'eeg', True),
    ('sub-01_desc-clean_custom.nii.gz', 'custom', 'nii.gz', True),
    ('participants.tsv', 'participants', 'tsv', True),
    ('events.json', 'events', 'json', True),
    ('T1w.json', 'T1w', 'json', True),
    ('sub-01_T1w', 'T1w', None, True),
    ('README', None, None, False),
    ('README.md', None, 'md', False),
    ('CHANGES', None, None, False),
    ('LICENSE.txt', None, 'txt', False),
    ('CITATION.cff', None, 'cff', False),
    ('.bidsignore', None, None, False),
    ('dataset_description.json', None, 'json', False),
    ('genetic_info.json', None, 'json', False),
    ('not_a_bids_name.tsv', None, 'tsv', False),
    ('custom_metadata.json', None, 'json', False),
])
def test_register_bids_file_suffix_extension(
    env: Env, tmp_path: Path, name: str, suffix: str | None, extension: str | None, has_suffix: bool,
):
    dataset = DbBidsDataset(path=Path('bids_imports/test'))
    env.db.add(dataset)
    env.db.flush()
    importer = BidsImporter(
        args=BidsImporterArgs(
            source_bids_path=tmp_path / 'source',
            type='raw',
            bids_validation=True,
            create_candidate=False,
            create_session=False,
            copy=True,
            verbose=False,
        ),
        data_dir_path=tmp_path,
        loris_bids_dataset=dataset,
    )
    stored_path = dataset.path / name
    full_path = tmp_path / stored_path
    full_path.parent.mkdir(parents=True)
    full_path.write_text('first import')
    # Classification must describe the stored name, even if the source name differs.
    source_path = importer.args.source_bids_path / 'original.json'

    file = get_or_create_loris_bids_file(env, importer, source_path, stored_path, parse_suffix=has_suffix)

    assert file.suffix == suffix
    assert file.extension == extension
    assert file.blake2b_hash == compute_file_blake2b_hash(full_path)

    # Reimport reuses the same row and updates its content hash.
    full_path.write_text('second import')

    reimported = get_or_create_loris_bids_file(env, importer, source_path, stored_path, parse_suffix=has_suffix)

    assert reimported.id == file.id
    assert reimported.suffix == suffix
    assert reimported.extension == extension
    assert reimported.blake2b_hash == compute_file_blake2b_hash(full_path)
    assert env.db.scalar(select(func.count()).select_from(type(file))) == 1


@pytest.mark.parametrize('copy', [True, False])
def test_static_files_have_no_suffix(env: Env, tmp_path: Path, copy: bool):
    dataset = DbBidsDataset(path=Path('bids_imports/test'))
    env.db.add(dataset)
    env.db.flush()
    source_path = tmp_path / 'source' if copy else tmp_path / dataset.path
    source_path.mkdir(parents=True)
    (source_path / 'README').write_text('Dataset documentation')
    (source_path / 'dataset_description.json').write_text('{"Name": "test"}')
    importer = BidsImporter(
        args=BidsImporterArgs(
            source_bids_path=source_path,
            type='raw',
            bids_validation=True,
            create_candidate=False,
            create_session=False,
            copy=copy,
            verbose=False,
        ),
        data_dir_path=tmp_path,
        loris_bids_dataset=dataset,
    )

    copy_bids_static_files(env, importer)
    copy_bids_static_files(env, importer)

    files = env.db.scalars(select(DbBidsFile).order_by(DbBidsFile.path)).all()
    assert [(file.path, file.suffix, file.extension) for file in files] == [
        (Path('README'), None, None),
        (Path('dataset_description.json'), None, 'json'),
    ]
    for file in files:
        full_path = tmp_path / dataset.path / file.path
        assert full_path.read_text() == (source_path / file.path).read_text()
        assert file.blake2b_hash == compute_file_blake2b_hash(full_path)
