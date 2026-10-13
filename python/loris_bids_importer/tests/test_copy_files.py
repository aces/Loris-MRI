from pathlib import Path

from lib.db.models.bids_dataset import DbBidsDataset
from lib.db.models.bids_file import DbBidsFile
from lib.db.models.candidate import DbCandidate
from lib.db.models.session import DbSession
from lib.env import Env
from loris_bids_utils.files.participants import BidsParticipantsTsvFile
from loris_bids_utils.files.sessions import BidsSessionsTsvFile
from loris_bids_utils.labels import BidsSessionLabel, BidsSubjectLabel
from sqlalchemy import select

from loris_bids_importer.copy_files import copy_bids_participants_file, copy_bids_sessions_file
from loris_bids_importer.importer import BidsImporter, BidsImporterArgs


def test_copy_bids_identity_files_uses_resolved_loris_labels(env: Env, tmp_path: Path):
    source_path = tmp_path / 'source'
    source_subject_path = source_path / 'sub-source01'
    source_subject_path.mkdir(parents=True)

    participants_path = source_path / 'participants.tsv'
    participants_path.write_text(
        'participant_id\tgroup\n'
        'sub-source01\tControl\n'
    )

    sessions_path = source_subject_path / 'sub-source01_sessions.tsv'
    sessions_path.write_text(
        'session_id\ttimepoint\n'
        'ses-baseline\tfirst\n'
    )

    candidate = DbCandidate(
        cand_id=123456,
        psc_id='LORIS001',
        registration_project_id=1,
        registration_site_id=1,
    )
    session = DbSession(
        candidate=candidate,
        visit_label='V1',
        project_id=1,
        site_id=1,
    )
    dataset = DbBidsDataset(path=Path('bids_imports/test'))
    env.db.add_all([candidate, session, dataset])
    env.db.flush()

    data_path = tmp_path / 'data'
    data_path.mkdir()
    importer = BidsImporter(
        args=BidsImporterArgs(
            source_bids_path=source_path,
            bids_config_path=None,
            type='raw',
            bids_validation=False,
            copy=True,
            verbose=False,
        ),
        data_dir_path=data_path,
        loris_bids_dataset=dataset,
    )

    source_participants = BidsParticipantsTsvFile.read(participants_path)
    source_sessions = BidsSessionsTsvFile.read(sessions_path)

    copy_bids_participants_file(
        env,
        importer,
        source_participants,
        {BidsSubjectLabel('source01'): candidate},
    )
    copy_bids_sessions_file(
        env,
        importer,
        source_sessions,
        candidate,
        {BidsSessionLabel('baseline'): session},
    )

    assert source_participants.rows[0].participant_id == 'source01'
    assert source_sessions.rows[0].session_id == 'baseline'

    copied_participants = BidsParticipantsTsvFile.read(data_path / dataset.path / 'participants.tsv')
    assert copied_participants.rows[0].participant_id == 'LORIS001'
    assert copied_participants.rows[0].data['group'] == 'Control'

    copied_sessions = BidsSessionsTsvFile.read(
        data_path / dataset.path / 'sub-LORIS001' / 'sub-LORIS001_sessions.tsv'
    )
    assert copied_sessions.rows[0].session_id == 'V1'
    assert copied_sessions.rows[0].data['timepoint'] == 'first'


def test_copy_bids_identity_files_updates_incremental_destination(env: Env, tmp_path: Path):
    source_path = tmp_path / 'source'
    source_subject_path = source_path / 'sub-source01'
    source_subject_path.mkdir(parents=True)

    participants_path = source_path / 'participants.tsv'
    participants_path.write_text('participant_id\tgroup\nsub-source01\tCurrent\n')
    sessions_path = source_subject_path / 'sub-source01_sessions.tsv'
    sessions_path.write_text('session_id\ttimepoint\nses-baseline\tcurrent\n')

    candidate = DbCandidate(
        cand_id=123456,
        psc_id='LORIS001',
        registration_project_id=1,
        registration_site_id=1,
    )
    session = DbSession(
        candidate=candidate,
        visit_label='V1',
        project_id=1,
        site_id=1,
    )
    dataset = DbBidsDataset(path=Path('bids_imports/test'))
    env.db.add_all([candidate, session, dataset])
    env.db.flush()

    data_path = tmp_path / 'data'
    destination_path = data_path / dataset.path
    destination_subject_path = destination_path / 'sub-LORIS001'
    destination_subject_path.mkdir(parents=True)
    (destination_path / 'participants.tsv').write_text(
        'participant_id\tgroup\n'
        'sub-LORIS001\tOutdated\n'
        'sub-LORIS999\tPreserved\n'
    )
    (destination_subject_path / 'sub-LORIS001_sessions.tsv').write_text(
        'session_id\ttimepoint\n'
        'ses-V1\toutdated\n'
        'ses-V9\tpreserved\n'
    )

    importer = BidsImporter(
        args=BidsImporterArgs(
            source_bids_path=source_path,
            bids_config_path=None,
            type='raw',
            bids_validation=False,
            copy=True,
            verbose=False,
        ),
        data_dir_path=data_path,
        loris_bids_dataset=dataset,
    )

    copy_bids_participants_file(
        env,
        importer,
        BidsParticipantsTsvFile.read(participants_path),
        {BidsSubjectLabel('source01'): candidate},
    )
    copy_bids_sessions_file(
        env,
        importer,
        BidsSessionsTsvFile.read(sessions_path),
        candidate,
        {BidsSessionLabel('baseline'): session},
    )

    participants = BidsParticipantsTsvFile.read(destination_path / 'participants.tsv')
    current_participant = participants.get_row('LORIS001')
    preserved_participant = participants.get_row('LORIS999')
    assert current_participant is not None
    assert current_participant.data['group'] == 'Current'
    assert preserved_participant is not None
    assert preserved_participant.data['group'] == 'Preserved'

    sessions = BidsSessionsTsvFile.read(destination_subject_path / 'sub-LORIS001_sessions.tsv')
    current_session = sessions.get_row('V1')
    preserved_session = sessions.get_row('V9')
    assert current_session is not None
    assert current_session.data['timepoint'] == 'current'
    assert preserved_session is not None
    assert preserved_session.data['timepoint'] == 'preserved'


def test_copy_bids_identity_files_only_registers_files_in_no_copy_mode(env: Env, tmp_path: Path):
    data_path = tmp_path / 'data'
    source_path = data_path / 'source'
    source_subject_path = source_path / 'sub-source01'
    source_subject_path.mkdir(parents=True)

    participants_path = source_path / 'participants.tsv'
    participants_contents = 'participant_id\tgroup\nsub-source01\tControl\n'
    participants_path.write_text(participants_contents)

    sessions_path = source_subject_path / 'sub-source01_sessions.tsv'
    sessions_contents = 'session_id\ttimepoint\nses-baseline\tfirst\n'
    sessions_path.write_text(sessions_contents)

    candidate = DbCandidate(
        cand_id=123456,
        psc_id='LORIS001',
        registration_project_id=1,
        registration_site_id=1,
    )
    session = DbSession(
        candidate=candidate,
        visit_label='V1',
        project_id=1,
        site_id=1,
    )
    dataset = DbBidsDataset(path=Path('source'))
    env.db.add_all([candidate, session, dataset])
    env.db.flush()

    importer = BidsImporter(
        args=BidsImporterArgs(
            source_bids_path=source_path,
            bids_config_path=None,
            type='raw',
            bids_validation=False,
            copy=False,
            verbose=False,
        ),
        data_dir_path=data_path,
        loris_bids_dataset=dataset,
    )

    copy_bids_participants_file(
        env,
        importer,
        BidsParticipantsTsvFile.read(participants_path),
        {BidsSubjectLabel('source01'): candidate},
    )
    copy_bids_sessions_file(
        env,
        importer,
        BidsSessionsTsvFile.read(sessions_path),
        candidate,
        {BidsSessionLabel('baseline'): session},
    )

    assert participants_path.read_text() == participants_contents
    assert sessions_path.read_text() == sessions_contents
    assert [bids_file.path for bids_file in env.db.scalars(select(DbBidsFile).order_by(DbBidsFile.path))] == [
        Path('participants.tsv'),
        Path('sub-source01/sub-source01_sessions.tsv'),
    ]
