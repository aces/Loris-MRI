from dataclasses import dataclass
from pathlib import Path
from unittest.mock import Mock

import pytest
from lib.db.models.bids_dataset import DbBidsDataset
from lib.db.models.bids_file import DbBidsFile
from lib.db.models.candidate import DbCandidate
from lib.db.models.cohort import DbCohort

# Import the HED schema referenced by models loaded by the import entry point.
from lib.db.models.hed_schema import DbHedSchema as DbHedSchema
from lib.db.models.project import DbProject
from lib.db.models.project_cohort import DbProjectCohort
from lib.db.models.session import DbSession
from lib.db.models.sex import DbSex
from lib.db.models.site import DbSite
from lib.db.models.visit import DbVisit
from lib.db.models.visit_window import DbVisitWindow
from lib.env import Env
from loris_bids_utils.files.participants import BidsParticipantsTsvFile, BidsParticipantTsvRow
from loris_bids_utils.files.sessions import BidsSessionsTsvFile, BidsSessionTsvRow
from loris_bids_utils.labels import BidsSessionLabel, BidsSubjectLabel, BidsSubjectSessionLabel
from loris_bids_utils.reader import BidsDatasetReader

from loris_bids_importer import main
from loris_bids_importer.config import (
    BidsCandidateConfig,
    BidsConfigFunctions,
    BidsSessionConfig,
    CreateBidsCandidateConfig,
    CreateBidsSessionConfig,
)
from loris_bids_importer.importer import BidsImporter, BidsImporterArgs
from loris_bids_importer.resolution.candidates import resolve_bids_candidate
from loris_bids_importer.resolution.dataset import resolve_bids_mappings
from loris_bids_importer.resolution.sessions import resolve_bids_session


@dataclass
class LorisRecords:
    project: DbProject
    site: DbSite
    cohort: DbCohort


@pytest.fixture
def loris_records(env: Env) -> LorisRecords:
    project = DbProject(id=1, name='Test Project', alias='TEST')
    site = DbSite(id=1, name='Test Site', alias='SITE')
    cohort = DbCohort(id=1, name='Control')
    env.db.add_all([
        project,
        site,
        cohort,
        DbProjectCohort(project_id=project.id, cohort_id=cohort.id),
        DbSex(name='Female'),
        DbVisit(id=1, name='Baseline', label='V1'),
        DbVisitWindow(visit_label='V1'),
        DbVisit(id=2, name='Follow-up', label='V2'),
        DbVisitWindow(visit_label='V2'),
    ])
    env.db.flush()
    return LorisRecords(project, site, cohort)


def test_resolve_created_candidate_and_session(env: Env, loris_records: LorisRecords):
    candidate = resolve_bids_candidate(
        env,
        BidsCandidateConfig(
            psc_id='LORIS001',
            create=CreateBidsCandidateConfig(
                registration_project=loris_records.project.alias,
                registration_site=loris_records.site.alias,
                sex='F',
            ),
        ),
    )

    assert candidate.psc_id == 'LORIS001'
    assert candidate.sex == 'Female'

    session = resolve_bids_session(
        env,
        candidate,
        BidsSessionConfig(
            visit_label='V1',
            create=CreateBidsSessionConfig(
                project=loris_records.project.alias,
                site=loris_records.site.alias,
                cohort=loris_records.cohort.name,
            ),
        ),
    )

    assert session.candidate is candidate
    assert session.visit_label == 'V1'
    assert session.visit_number == 1
    assert session.project_id == loris_records.project.id
    assert session.site_id == loris_records.site.id
    assert session.cohort_id == loris_records.cohort.id

    second_session = resolve_bids_session(
        env,
        candidate,
        BidsSessionConfig(
            visit_label='V2',
            create=CreateBidsSessionConfig(
                project=loris_records.project.alias,
                site=loris_records.site.alias,
                cohort=loris_records.cohort.name,
            ),
        ),
    )

    assert second_session.visit_number == 2


def test_resolve_candidate_identifier_mismatch(env: Env, loris_records: LorisRecords):
    candidate = DbCandidate(
        cand_id=123456,
        psc_id='LORIS001',
        registration_project_id=loris_records.project.id,
        registration_site_id=loris_records.site.id,
    )
    env.db.add(candidate)
    env.db.flush()

    with pytest.raises(Exception, match='mismatch'):
        resolve_bids_candidate(env, BidsCandidateConfig(cand_id=123456, psc_id='OTHER'))


def test_resolve_bids_mappings_passes_stable_metadata(
    env: Env,
    loris_records: LorisRecords,
    tmp_path: Path,
):
    candidate = DbCandidate(
        cand_id=123456,
        psc_id='LORIS001',
        registration_project_id=loris_records.project.id,
        registration_site_id=loris_records.site.id,
    )
    session = DbSession(
        candidate=candidate,
        visit_label='V1',
        visit_number=1,
        project_id=loris_records.project.id,
        site_id=loris_records.site.id,
        cohort_id=loris_records.cohort.id,
    )
    env.db.add_all([candidate, session])
    env.db.flush()

    dataset_path = make_bids_dataset(tmp_path)
    bids = BidsDatasetReader(dataset_path, derivatives=False, validate=False)

    def get_candidate_config(
        hook_env: Env,
        subject_label: BidsSubjectLabel,
        participant_row: BidsParticipantTsvRow | None,
    ) -> BidsCandidateConfig:
        assert hook_env is env
        assert subject_label == 'source01'
        assert participant_row is not None
        assert participant_row.data['group'] == 'source-group'
        return BidsCandidateConfig(psc_id='LORIS001')

    def get_session_config(
        hook_env: Env,
        candidate_config: BidsCandidateConfig,
        subject_label: BidsSubjectLabel,
        session_label: BidsSessionLabel | None,
        participant_row: BidsParticipantTsvRow | None,
        session_row: BidsSessionTsvRow | None,
    ) -> BidsSessionConfig:
        assert hook_env is env
        assert candidate_config == BidsCandidateConfig(psc_id='LORIS001')
        assert subject_label == 'source01'
        assert session_label == 'sourcevisit'
        assert participant_row is not None
        assert participant_row.data['group'] == 'source-group'
        assert session_row is not None
        assert session_row.data['timepoint'] == 'baseline'
        return BidsSessionConfig(visit_label='V1')

    config = BidsConfigFunctions(
        get_candidate=get_candidate_config,
        get_session=get_session_config,
    )

    mappings = resolve_bids_mappings(env, bids, config)

    assert mappings.candidates == {'source01': candidate}
    assert mappings.sessions == {
        BidsSubjectSessionLabel(
            BidsSubjectLabel('source01'),
            BidsSessionLabel('sourcevisit'),
        ): session
    }


def make_bids_dataset(tmp_path: Path) -> Path:
    dataset = tmp_path / 'dataset'
    session = dataset / 'sub-source01' / 'ses-sourcevisit' / 'anat'
    session.mkdir(parents=True)

    (dataset / 'dataset_description.json').write_text(
        '{"Name": "Mapping test", "BIDSVersion": "1.8.0"}'
    )
    (dataset / 'participants.tsv').write_text(
        'participant_id\tgroup\nsub-source01\tsource-group\n'
    )
    (dataset / 'sub-source01' / 'sub-source01_sessions.tsv').write_text(
        'session_id\ttimepoint\nses-sourcevisit\tbaseline\n'
    )
    (dataset / 'sub-source01' / 'sub-source01_sessions.json').write_text(
        '{"timepoint": {"Description": "Study time point"}}'
    )
    (session / 'sub-source01_ses-sourcevisit_T1w.nii.gz').touch()
    return dataset


def make_filtering_dataset(tmp_path: Path) -> BidsDatasetReader:
    dataset = tmp_path / 'source'
    dataset.mkdir(parents=True)
    (dataset / 'dataset_description.json').write_text('{"Name": "Filtering", "BIDSVersion": "1.8.0"}')
    (dataset / 'participants.tsv').write_text(
        'participant_id\tgroup\nsub-skip\tControl\nsub-empty\tControl\nsub-keep\tControl\n'
    )
    for subject in ('skip', 'empty', 'keep'):
        subject_path = dataset / f'sub-{subject}'
        subject_path.mkdir()
        (subject_path / f'sub-{subject}_sessions.tsv').write_text(
            'session_id\n' + ''.join(f'ses-{session}\n' for session in ('baseline', 'followup'))
        )
        for session in ('baseline', 'followup'):
            session_path = subject_path / f'ses-{session}' / 'anat'
            session_path.mkdir(parents=True)
            (session_path / f'sub-{subject}_ses-{session}_T1w.nii.gz').touch()
    return BidsDatasetReader(dataset, derivatives=False, validate=False)


def filtering_config(env: Env) -> BidsConfigFunctions:
    def get_candidate(
        hook_env: Env,
        subject_label: BidsSubjectLabel,
        participant_row: BidsParticipantTsvRow | None,
    ) -> BidsCandidateConfig | None:
        assert hook_env is env
        if subject_label == 'skip':
            return None
        return BidsCandidateConfig(
            psc_id=subject_label.upper(),
            create=CreateBidsCandidateConfig(registration_project='TEST', registration_site='SITE'),
        )

    def get_session(
        hook_env: Env,
        candidate_config: BidsCandidateConfig,
        subject_label: BidsSubjectLabel,
        session_label: BidsSessionLabel | None,
        participant_row: BidsParticipantTsvRow | None,
        session_row: BidsSessionTsvRow | None,
    ) -> BidsSessionConfig | None:
        assert hook_env is env
        assert subject_label != 'skip', "Skipped subjects must not invoke session hooks"
        assert candidate_config.psc_id == subject_label.upper()
        # All session configuration runs before the importer creates any candidates.
        assert env.db.query(DbCandidate).count() == 0
        if subject_label == 'empty' or session_label == 'followup':
            return None
        return BidsSessionConfig(
            visit_label='V1',
            create=CreateBidsSessionConfig(project='TEST', site='SITE', cohort='Control'),
        )

    return BidsConfigFunctions(get_candidate=get_candidate, get_session=get_session)


def test_filtering_resolves_only_selected_records(env: Env, loris_records: LorisRecords, tmp_path: Path):
    bids = make_filtering_dataset(tmp_path)
    mappings = resolve_bids_mappings(env, bids, filtering_config(env))

    assert list(mappings.candidates) == ['keep']
    assert [(key.subject, key.session) for key in mappings.sessions] == [('keep', 'baseline')]
    assert [candidate.psc_id for candidate in env.db.query(DbCandidate)] == ['KEEP']
    assert [session.visit_label for session in env.db.query(DbSession)] == ['V1']


@pytest.mark.parametrize('skip_subject', [True, False])
def test_filtered_subject_needs_no_database_identity(env: Env, tmp_path: Path, skip_subject: bool):
    bids = BidsDatasetReader(make_bids_dataset(tmp_path), derivatives=False, validate=False)

    def get_session(*args: object):
        assert not skip_subject
        return None

    mappings = resolve_bids_mappings(env, bids, BidsConfigFunctions(
        get_candidate=Mock(return_value=None if skip_subject else BidsCandidateConfig(cand_id=999999)),
        get_session=get_session,
    ))

    assert mappings.candidates == {}
    assert mappings.sessions == {}
    assert env.db.query(DbCandidate).count() == 0
    assert env.db.query(DbSession).count() == 0


@pytest.mark.parametrize('candidate_config', [
    BidsCandidateConfig(),
    BidsCandidateConfig(psc_id=''),
    BidsCandidateConfig(cand_id='123456'),  # type: ignore[arg-type]
    BidsCandidateConfig(psc_id=123456),  # type: ignore[arg-type]
    BidsCandidateConfig(psc_id='NEW', create='invalid'),  # type: ignore[arg-type]
    BidsCandidateConfig(cand_id=123456, create=CreateBidsCandidateConfig('TEST', 'SITE')),
    BidsCandidateConfig(psc_id='NEW', create=CreateBidsCandidateConfig('', 'SITE')),
    BidsCandidateConfig(psc_id='NEW', create=CreateBidsCandidateConfig('TEST', 'SITE', sex=1)),  # type: ignore[arg-type]
    BidsCandidateConfig(psc_id='NEW', create=CreateBidsCandidateConfig('TEST', 'SITE', date_of_birth='bad')),  # type: ignore[arg-type]
    'invalid',
])
def test_invalid_candidate_config_fails_before_session_hook(
    env: Env, tmp_path: Path, candidate_config: BidsCandidateConfig | str,
):
    bids = BidsDatasetReader(make_bids_dataset(tmp_path), derivatives=False, validate=False)
    called = False

    def get_session(*args: object):
        nonlocal called
        called = True
        return None

    with pytest.raises(ExceptionGroup, match='get the LORIS candidate configurations') as error:
        resolve_bids_mappings(env, bids, BidsConfigFunctions(
            get_candidate=Mock(return_value=candidate_config),
            get_session=get_session,
        ))

    assert 'source01' in str(error.value.exceptions[0])
    assert not called
    assert env.db.query(DbCandidate).count() == 0


@pytest.mark.parametrize('invalid_return', [False, True])
def test_session_configuration_errors_are_not_skips(env: Env, tmp_path: Path, invalid_return: bool):
    bids = BidsDatasetReader(make_bids_dataset(tmp_path), derivatives=False, validate=False)

    def get_session(*args: object):
        if invalid_return:
            return 'invalid'
        raise ValueError('Bad session metadata')

    with pytest.raises(ExceptionGroup, match='get the LORIS session configurations'):
        resolve_bids_mappings(env, bids, BidsConfigFunctions(
            get_candidate=Mock(return_value=BidsCandidateConfig(psc_id='NEW')),
            get_session=get_session,  # type: ignore[arg-type]
        ))
    assert env.db.query(DbCandidate).count() == 0


def test_failed_session_resolution_rolls_back_candidate_creation(
    env: Env, loris_records: LorisRecords, tmp_path: Path,
):
    env.db.commit()
    bids = BidsDatasetReader(make_bids_dataset(tmp_path), derivatives=False, validate=False)
    with pytest.raises(ExceptionGroup, match='get or create the LORIS sessions'):
        resolve_bids_mappings(env, bids, BidsConfigFunctions(
            get_candidate=Mock(return_value=BidsCandidateConfig(
                psc_id='NEW', create=CreateBidsCandidateConfig('TEST', 'SITE'),
            )),
            get_session=Mock(return_value=BidsSessionConfig(visit_label='MISSING')),
        ))
    assert env.db.query(DbCandidate).count() == 0


@pytest.mark.parametrize('copy', [True, False])
def test_import_filters_acquisitions_and_identity_metadata(
    env: Env, loris_records: LorisRecords, tmp_path: Path, monkeypatch: pytest.MonkeyPatch, copy: bool,
):
    bids = make_filtering_dataset(tmp_path)
    original_tsvs = {path: path.read_bytes() for path in bids.path.rglob('*.tsv')}
    args = BidsImporterArgs(
        source_bids_path=bids.path, bids_config_path=None, type='raw',
        bids_validation=False, copy=copy, verbose=False,
    )
    dataset = DbBidsDataset(path=Path('destination' if copy else 'source'))
    env.db.add(dataset)
    env.db.flush()
    importer = BidsImporter(args=args, data_dir_path=tmp_path, loris_bids_dataset=dataset)
    monkeypatch.setattr(main, 'load_bids_config', Mock(return_value=filtering_config(env)))
    monkeypatch.setattr(main, 'make_bids_importer', Mock(return_value=importer))
    import_session = Mock()
    monkeypatch.setattr(main, 'import_bids_session', import_session)

    main.import_bids_dataset(env, args)

    import_session.assert_called_once()
    assert import_session.call_args.args[2].subject.label == 'keep'
    assert import_session.call_args.args[2].label == 'baseline'
    assert import_session.call_args.args[3].candidate.psc_id == 'KEEP'
    assert {path: path.read_bytes() for path in original_tsvs} == original_tsvs
    registered_paths = {str(file.source_path) for file in env.db.query(DbBidsFile)}
    assert 'sub-keep/sub-keep_sessions.tsv' in registered_paths
    assert not any('sub-skip' in path or 'sub-empty' in path for path in registered_paths)
    if copy:
        destination = tmp_path / 'destination'
        participants = BidsParticipantsTsvFile.read(destination / 'participants.tsv')
        assert [row.participant_id for row in participants.rows] == ['KEEP']
        sessions = BidsSessionsTsvFile.read(destination / 'sub-KEEP' / 'sub-KEEP_sessions.tsv')
        assert [row.session_id for row in sessions.rows] == ['V1']
        assert not (destination / 'sub-empty').exists()
        assert not (destination / 'sub-skip').exists()


def test_entirely_filtered_import_is_a_noop(env: Env, tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    bids = make_filtering_dataset(tmp_path)
    args = BidsImporterArgs(
        source_bids_path=bids.path, bids_config_path=None, type='raw',
        bids_validation=False, copy=True, verbose=False,
    )
    monkeypatch.setattr(main, 'load_bids_config', Mock(return_value=BidsConfigFunctions(
        get_candidate=Mock(return_value=BidsCandidateConfig(psc_id='NOTINLORIS')),
        get_session=Mock(return_value=None),
    )))
    make_importer = Mock()
    monkeypatch.setattr(main, 'make_bids_importer', make_importer)

    main.import_bids_dataset(env, args)

    make_importer.assert_not_called()
    assert env.db.query(DbCandidate).count() == 0
    assert env.log_file_path is not None
    assert 'Nothing to import' in env.log_file_path.read_text()
    assert env.db.query(DbBidsDataset).count() == 0


@pytest.mark.parametrize('selected', [True, False])
def test_sessionless_dataset_filtering(
    env: Env, loris_records: LorisRecords, tmp_path: Path, selected: bool,
):
    dataset = tmp_path / 'sessionless'
    anat = dataset / 'sub-source01' / 'anat'
    anat.mkdir(parents=True)
    (dataset / 'dataset_description.json').write_text('{"Name": "Sessionless", "BIDSVersion": "1.8.0"}')
    (anat / 'sub-source01_T1w.nii.gz').touch()
    bids = BidsDatasetReader(dataset, derivatives=False, validate=False)
    candidate_config = BidsCandidateConfig(
        psc_id='NEW', create=CreateBidsCandidateConfig('TEST', 'SITE'),
    )

    def get_session(
        hook_env: Env,
        configured_candidate: BidsCandidateConfig,
        subject_label: BidsSubjectLabel,
        session_label: BidsSessionLabel | None,
        participant_row: BidsParticipantTsvRow | None,
        session_row: BidsSessionTsvRow | None,
    ) -> BidsSessionConfig | None:
        assert configured_candidate is candidate_config
        assert session_label is None
        assert session_row is None
        if not selected:
            return None
        return BidsSessionConfig('V1', create=CreateBidsSessionConfig('TEST', 'SITE', 'Control'))

    mappings = resolve_bids_mappings(env, bids, BidsConfigFunctions(
        get_candidate=Mock(return_value=candidate_config), get_session=get_session,
    ))
    assert len(mappings.candidates) == int(selected)
    assert len(mappings.sessions) == int(selected)
    assert env.db.query(DbCandidate).count() == int(selected)
    if selected:
        key = next(iter(mappings.sessions))
        assert key.session is None
        assert mappings.sessions[key].visit_label == 'V1'
