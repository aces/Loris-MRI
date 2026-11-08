from pathlib import Path

import pytest
from lib.db.models.bids_dataset import DbBidsDataset
from lib.db.models.bids_file import DbBidsFile
from lib.env import Env
from loris_utils.crypto import compute_path_blake2b_hash
from sqlalchemy import func, select

from loris_bids_importer.copy_files import copy_bids_static_files
from loris_bids_importer.dataset import get_or_create_loris_bids_file
from loris_bids_importer.importer import BidsImporter, BidsImporterArgs


@pytest.mark.parametrize('existing', [False, True])
@pytest.mark.parametrize(('name', 'suffix', 'extension', 'parse_bids_name', 'entities'), [
    ('sub-01_ses-V1_task-rest_run-01_echo-02_bold.nii.gz', 'bold', 'nii.gz', True,
     {'sub': '01', 'ses': 'V1', 'task': 'rest', 'run': '01', 'echo': '02'}),
    ('sub-01_task-rest_meg.ds', 'meg', 'ds', True, {'sub': '01', 'task': 'rest'}),
    ('sub-01_T1w.nii.gz', 'T1w', 'nii.gz', True, {'sub': '01'}),
    ('sub-01_T1w.json', 'T1w', 'json', True, {'sub': '01'}),
    ('sub-01_task-rest_events.tsv', 'events', 'tsv', True, {'sub': '01', 'task': 'rest'}),
    ('sub-01_task-rest_physio.tsv.gz', 'physio', 'tsv.gz', True, {'sub': '01', 'task': 'rest'}),
    ('sub-01_task-rest_eeg.vhdr', 'eeg', 'vhdr', True, {'sub': '01', 'task': 'rest'}),
    ('sub-01_task-rest_eeg.eeg', 'eeg', 'eeg', True, {'sub': '01', 'task': 'rest'}),
    ('sub-01_desc-clean_custom.nii.gz', 'custom', 'nii.gz', True, {'sub': '01', 'desc': 'clean'}),
    ('participants.tsv', 'participants', 'tsv', True, {}),
    ('events.json', 'events', 'json', True, {}),
    ('T1w.json', 'T1w', 'json', True, {}),
    ('sub-01_T1w', 'T1w', None, True, {'sub': '01'}),
    ('README', None, None, False, {}),
    ('README.md', None, 'md', False, {}),
    ('CHANGES', None, None, False, {}),
    ('LICENSE.txt', None, 'txt', False, {}),
    ('CITATION.cff', None, 'cff', False, {}),
    ('.bidsignore', None, None, False, {}),
    ('dataset_description.json', None, 'json', False, {}),
    ('genetic_info.json', None, 'json', False, {}),
    ('not_a_bids_name.tsv', None, 'tsv', False, {}),
    ('custom_metadata.json', None, 'json', False, {}),
])
def test_register_bids_file_name(
    env: Env, tmp_path: Path, name: str, suffix: str | None, extension: str | None,
    parse_bids_name: bool, entities: dict[str, str], existing: bool,
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
    if extension == 'ds':
        full_path.mkdir()
        content_path = full_path / 'recording.meg4'
    else:
        content_path = full_path
    content_path.write_text('first import')
    # Classification must describe the stored name, even if the source name differs.
    source_path = importer.args.source_bids_path / 'original.json'

    if existing:
        # Files registered before this feature retain their missing name-derived fields.
        env.db.add(DbBidsFile(
            dataset_id=dataset.id, path=Path(name), blake2b_hash='old', derivative=False,
        ))
        env.db.flush()
        suffix, extension, entities = None, None, {}

    file = get_or_create_loris_bids_file(env, importer, source_path, stored_path, parse_bids_name=parse_bids_name)

    assert file.suffix == suffix
    assert file.extension == extension
    env.db.expire(file, ['entities'])
    assert {entity.key: entity.value for entity in file.entities} == entities
    assert all(entity.id is not None and entity.file_id == file.id for entity in file.entities)
    entity_ids = [entity.id for entity in file.entities]
    assert file.blake2b_hash == compute_path_blake2b_hash(full_path)

    # Reimport reuses the same row and updates its content hash.
    content_path.write_text('second import')

    reimported = get_or_create_loris_bids_file(env, importer, source_path, stored_path, parse_bids_name=parse_bids_name)

    assert reimported.id == file.id
    assert reimported.suffix == suffix
    assert reimported.extension == extension
    env.db.expire(reimported, ['entities'])
    assert {entity.key: entity.value for entity in reimported.entities} == entities
    assert [entity.id for entity in reimported.entities] == entity_ids
    assert reimported.blake2b_hash == compute_path_blake2b_hash(full_path)
    assert env.db.scalar(select(func.count()).select_from(type(file))) == 1


@pytest.mark.parametrize('copy', [True, False])
def test_static_files_have_no_suffix_or_entities(env: Env, tmp_path: Path, copy: bool):
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
        assert file.entities == []
        full_path = tmp_path / dataset.path / file.path
        assert full_path.read_text() == (source_path / file.path).read_text()
        assert file.blake2b_hash == compute_path_blake2b_hash(full_path)
