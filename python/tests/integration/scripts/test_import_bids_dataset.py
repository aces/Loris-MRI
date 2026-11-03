import json
from datetime import datetime
from pathlib import Path

from loris_utils.crypto import compute_directory_blake2b_hash, compute_file_blake2b_hash
from loris_utils.fs import iter_all_dir_files
from sqlalchemy.orm import Session as Database

from lib.db.queries.bids_dataset import try_get_bids_dataset_with_path
from lib.db.queries.bids_event_dataset_mapping import get_bids_event_dataset_mappings_with_project_id
from lib.db.queries.bids_file import try_get_bids_file_with_dataset_id_path
from lib.db.queries.candidate import try_get_candidate_with_psc_id
from lib.db.queries.config import set_config_with_setting_name
from lib.db.queries.meg_ctf_head_shape import try_get_meg_ctf_head_shape_file_with_path
from lib.db.queries.physio_file import try_get_physio_file_with_path
from lib.db.queries.session import try_get_session_with_cand_id_visit_label
from lib.physio.parameters import get_physio_file_parameters_dict
from tests.util.database import get_integration_database_session
from tests.util.file_system import assert_files_exist
from tests.util.run_integration_script import run_integration_script


def test_import_eeg_bids_dataset():
    db = get_integration_database_session()

    # Enable EEG chunking.
    set_config_with_setting_name(db, 'useEEGBrowserVisualizationComponents', 'true')
    db.commit()

    process = run_integration_script([
        'import-bids-dataset',
        '--create-candidate', '--create-session',
        '--type', 'raw',
        '--directory', '/data/loris/incoming/Face13',
    ])

    # Check the return code.
    assert process.returncode == 0
    assert process.stderr == ""

    # Check that the candidate and sessions are present in the database.
    candidate = try_get_candidate_with_psc_id(db, 'OTT166')
    assert candidate is not None
    session = try_get_session_with_cand_id_visit_label(db, candidate.cand_id, 'V1')
    assert session is not None

    # Check that the physiological file has been inserted in the database.
    file = try_get_physio_file_with_path(
        db,
        Path('bids_imports/Face13_BIDSVersion_1.1.0/sub-OTT166/ses-V1/eeg/sub-OTT166_ses-V1_task-faceO_eeg.edf'),
    )

    assert file is not None
    assert len(file.channels) == 128
    assert len(file.event_files) == 1
    assert len(file.task_events) == 3185
    assert file.acquisition_time == datetime(2025, 10, 10, 15, 1, 10)
    assert file.archive is not None
    assert file.archive.path == Path('bids_imports/Face13_BIDSVersion_1.1.0/sub-OTT166/ses-V1/eeg/sub-OTT166_ses-V1_task-faceO_eeg.tgz')  # ruff:ignore[line-too-long]
    assert file.event_archive is not None
    assert file.event_archive.path == Path('bids_imports/Face13_BIDSVersion_1.1.0/sub-OTT166/ses-V1/eeg/sub-OTT166_ses-V1_task-faceO_events.tgz')  # ruff:ignore[line-too-long]

    # Check that the physiological file parameters has been inserted in the database.
    file_parameters = get_physio_file_parameters_dict(db, file.id)
    assert file_parameters == {
        'TaskName': 'FaceHouseCheck',
        'TaskDescription': 'Visual presentation of oval cropped face and house images both upright and inverted. Rare left or right half oval checkerboards were presetned as targets for keypress response.',  # ruff:ignore[line-too-long]
        'InstitutionName': 'Brock University',
        'InstitutionAddress': '500 Glenridge Ave, St.Catharines, Ontario',
        'SamplingFrequency': '256',
        'EEGChannelCount': '128',
        'EOGChannelCount': '7',
        'EMGChannelCount': '0',
        'ECGChannelCount': '0',
        'EEGReference': 'CMS',
        'MiscChannelCount': '0',
        'TriggerChannelCount': '0',
        'PowerLineFrequency': '60',
        'EEGPlacementScheme': 'Custom equidistant 128 channel BioSemi montage established in coordination with Judith Schedden McMaster Univertisy',  # ruff:ignore[line-too-long]
        'Manufacturer': 'BioSemi',
        'CapManufacturer': 'ElectroCap International',
        'HardwareFilters': 'n/a',
        'SoftwareFilters': 'n/a',
        'RecordingType': 'continuous',
        'RecordingDuration': '1119',
        'eegjson_file': 'bids_imports/Face13_BIDSVersion_1.1.0/sub-OTT166/ses-V1/eeg/sub-OTT166_ses-V1_task-faceO_eeg.json',  # ruff:ignore[line-too-long]
        'physiological_json_file_blake2b_hash': 'f762bbf2e4699fbe47a53f2b7c2f990dc401d7aa57a6b4ba37aa04acdc2748feb42ee058b874a14fae7c14f673280847e40a60771b3c397a0cf5abdb8c05077a',  # ruff:ignore[line-too-long]
        'physiological_file_blake2b_hash': '8c24c5907b724d659f38c65bfffc754003a586961ea9e25ed5fa0741a2691ed217e29553020230553c84c0b5978edf64624747d31623f6267cbd36eba8b70891',  # ruff:ignore[line-too-long]
        'electrode_file_blake2b_hash': '0206db2650ae5a07e4225ff87b6fb2a6bfcf6ea088dd8cdfd77d04e9e25a171ffe68878aa156478babb32dcaf9b46459f87fe0516b728278cc0d9372a0d49299',  # ruff:ignore[line-too-long]
        'channel_file_blake2b_hash': '7b91e3650086ef50ecc00f1c50e17e7ad8dc39c484536bbc2423af4be7d2b50a3a0010f840d457fec68fbfb3e136edf4d616a31bab0ca09ed686f555727341dd',  # ruff:ignore[line-too-long]
        'event_file_blake2b_hash': '532aa0b52749eb9ee52c2bbb65fa7b1d00d7126cb9a4e10bd4b9dbb4c5527b06e30acdaf17d5806e81d3ce8ad224a9f456e27aba1bf8b92fd43522837c7ffec7',  # ruff:ignore[line-too-long]
        'electrophysiology_chunked_dataset_path': 'chunks/Face13_BIDSVersion_1.1.0_chunks/sub-OTT166_ses-V1_task-faceO_eeg.chunks',  # ruff:ignore[line-too-long]
        'scan_acquisition_time': '2025-10-10 15:01:10.720100+00:00',
        'age_at_scan': 'None',
        'scans_tsv_file': 'bids_imports/Face13_BIDSVersion_1.1.0/sub-OTT166/ses-V1/sub-OTT166_ses-V1_scans.tsv',
        'scans_tsv_file_blake2hash': '4d9b695ba6b35257531b96375ca15c36179b08360f373c46425d958e406132b84ad029113ed4be5e458e762a8af0792ddde5127b5044778c8c8705d8df8f8621',  # ruff:ignore[line-too-long]
    }

    # Check that the event files has been inserted in the database.
    bids_event_dataset_mappings = get_bids_event_dataset_mappings_with_project_id(db, session.project.id)
    assert len(bids_event_dataset_mappings) == 12

    # Check that the BIDS files have been copied.
    assert_files_exist('/data/loris/bids_imports', {
        'Face13_BIDSVersion_1.1.0': {
            'dataset_description.json': None,
            'events.json': None,
            'participants.tsv': None,
            'README': None,
            'sub-OTT166': {
                'ses-V1': {
                    'sub-OTT166_ses-V1_scans.tsv': None,
                    'eeg': {
                        'sub-OTT166_ses-V1_task-faceO_channels.tsv': None,
                        'sub-OTT166_ses-V1_task-faceO_eeg.edf': None,
                        'sub-OTT166_ses-V1_task-faceO_eeg.json': None,
                        'sub-OTT166_ses-V1_task-faceO_electrodes.tsv': None,
                        'sub-OTT166_ses-V1_task-faceO_events.tsv': None,
                    }
                }
            }
        }
    })

    assert_bids_dataset_registered(
        db,
        Path('bids_imports/Face13_BIDSVersion_1.1.0'),
    )

    # Check that the chunk files have been created.
    assert_files_exist('/data/loris/chunks', {
        'Face13_BIDSVersion_1.1.0_chunks': {
            'sub-OTT166_ses-V1_task-faceO_eeg.chunks': {
                'index.json': None,
                'raw': {
                    '0': {
                        str(i): {
                            '0': {
                                '0.buf': None,
                                '1.buf': None,
                            }
                        } for i in range(0, 128)
                    },
                    '1': {
                        str(i): {
                            '0': {
                                f'{j}.buf': None for j in range(0, 58)
                            }
                        } for i in range(0, 128)
                    }
                }
            }
        }
    })


def test_import_mri_bids_dataset():
    db = get_integration_database_session()

    process = run_integration_script([
        'import-bids-dataset',
        '--create-candidate', '--create-session',
        '--directory', '/data/loris/incoming/DCC090_587630_V2',
    ])

    # Check the return code.
    assert process.returncode == 0
    assert process.stderr == (
        "WARNING: No events dictionary files (events.json) in root directory.\n"
        "WARNING: No 'scans.tsv' file found, 'scans.tsv' data will be ignored.\n"
        "WARNING: No 'scans.tsv' file found, 'scans.tsv' data will be ignored.\n"
    )

    # Check that the candidate and sessions are present in the database.
    candidate = try_get_candidate_with_psc_id(db, 'DCC090')
    assert candidate is not None
    session = try_get_session_with_cand_id_visit_label(db, candidate.cand_id, 'V2')
    assert session is not None

    # Check that the files has been inserted in the database.
    assert len(session.files) == 5

    # Check that the BIDS files have been copied.
    assert_files_exist('/data/loris/bids_imports', {
        'DCC090_587630_V2_BIDSVersion_1.8.0': {
            'dataset_description.json': None,
            'participants.tsv': None,
            'sub-DCC090': {
                'ses-V2': {
                    'anat': {
                        'sub-DCC090_ses-V2_acq-spc3p2_run-4_T2w.json': None,
                        'sub-DCC090_ses-V2_acq-spc3p2_run-4_T2w.nii.gz': None,
                        'sub-DCC090_ses-V2_acq-tfl3p2_run-3_T1w.json': None,
                        'sub-DCC090_ses-V2_acq-tfl3p2_run-3_T1w.nii.gz': None,
                        'sub-DCC090_ses-V2_acq-tse2p2_run-2_echo-1_T2w.json': None,
                        'sub-DCC090_ses-V2_acq-tse2p2_run-2_echo-1_T2w.nii.gz': None,
                        'sub-DCC090_ses-V2_acq-tse2p2_run-2_echo-2_T2w.json': None,
                        'sub-DCC090_ses-V2_acq-tse2p2_run-2_echo-2_T2w.nii.gz': None,
                    },
                    'dwi': {
                        'sub-DCC090_ses-V2_acq-epb0_dir-AP_run-5_dwi.bval': None,
                        'sub-DCC090_ses-V2_acq-epb0_dir-AP_run-5_dwi.bvec': None,
                        'sub-DCC090_ses-V2_acq-epb0_dir-AP_run-5_dwi.json': None,
                        'sub-DCC090_ses-V2_acq-epb0_dir-AP_run-5_dwi.nii.gz': None,
                    },
                }
            }
        }
    })

    assert_bids_dataset_registered(
        db,
        Path('bids_imports/DCC090_587630_V2_BIDSVersion_1.8.0'),
    )


def test_import_meg_ctf_bids_dataset():
    db = get_integration_database_session()

    # ds000246 has no session entity, so select the visit used when creating its LORIS session.
    set_config_with_setting_name(db, 'default_bids_vl', 'V1')
    # Enable MEG chunking.
    set_config_with_setting_name(db, 'useEEGBrowserVisualizationComponents', 'true')
    db.commit()

    process = run_integration_script([
        'import-bids-dataset',
        '--type', 'raw',
        '--directory', '/data/loris/incoming/ds000246',
    ])

    assert process.returncode == 0
    assert "No events dictionary files (events.json) in root directory." in process.stderr
    assert "No events file found for acquisition 'sub-BS0001_task-AEF_meg.ds'." in process.stderr

    candidate = try_get_candidate_with_psc_id(db, 'BS0001')
    assert candidate is not None
    session = try_get_session_with_cand_id_visit_label(db, candidate.cand_id, 'V1')
    assert session is not None
    assert session.project.name == 'Brainstorm'

    dataset_path = Path('bids_imports/MEG_BIDS_Brainstorm_data_sample_BIDSVersion_1.4.1')
    meg_path = dataset_path / 'sub-BS0001/ses-V1/meg'
    ctf_path = meg_path / 'sub-BS0001_ses-V1_task-AEF_meg.ds'

    file = try_get_physio_file_with_path(db, ctf_path)
    assert file is not None
    assert file.type == 'ctf'
    assert file.modality is not None
    assert file.modality.name == 'meg'
    assert file.output_type.name == 'raw'
    assert file.acquisition_time == datetime(1925, 1, 1, 9, 43)
    assert len(file.channels) == 340

    parameters = get_physio_file_parameters_dict(db, file.id)
    assert parameters == {
        'InstitutionName': 'McConnell Brain Imaging Centre, McGill University',
        'InstitutionAddress': '3801 University St., Montreal, QC, Canada',
        'Manufacturer': 'CTF',
        'ManufacturersModelName': 'CTF-275: OMEGA 2000',
        'SoftwareVersions': 'Acq 5.4.2-linux-20070507',
        'TaskName': 'AEF',
        'SamplingFrequency': '2400',
        'PowerLineFrequency': '60',
        'MEGChannelCount': '274',
        'MEGREFChannelCount': '26',
        'EEGChannelCount': '2',
        'EOGChannelCount': '2',
        'ECGChannelCount': '1',
        'EMGChannelCount': '0',
        'MiscChannelCount': '0',
        'SoftwareFilters': "{'SpatialCompensation': {'GradientOrder': '3rd'}}",
        'DewarPosition': 'Upright',
        'RecordingDuration': '10',
        'RecordingType': 'continuous',
        'EpochLength': '0',
        'ContinuousHeadLocalization': 'True',
        'HeadCoilFrequency': '[1470, 1530, 1590]',
        'MaxMovement': '0.000803443395641537',
        'DigitizedLandmarks': 'True',
        'DigitizedHeadPoints': 'True',
        'electrophysiology_chunked_dataset_path': 'chunks/MEG_BIDS_Brainstorm_data_sample_BIDSVersion_1.4.1_chunks/sub-BS0001_ses-V1_task-AEF_meg.chunks',  # ruff: ignore[line-too-long]
        'physiological_file_blake2b_hash': 'e5b46912d50420a269cfafdca35a94001b57c7ff93753d03cdfd8ba28178bd74da308810ecae244d061fb40d5cd17e25920680bcaa886260edb7b40d5b2c421b',  # ruff: ignore[line-too-long]
        'channel_file_blake2b_hash': '9b294f17ea6497d58f91ff303ddafec3e643d415718ac04b0dcfe5f6e6c7355f06005ee876d9ad374eee6ca5416e3b957fb6baebd3caebd806c9477475c66222',  # ruff: ignore[line-too-long]
    }

    chunk_path = Path(
        'chunks/MEG_BIDS_Brainstorm_data_sample_BIDSVersion_1.4.1_chunks/'
        'sub-BS0001_ses-V1_task-AEF_meg.chunks'
    )
    assert parameters['electrophysiology_chunked_dataset_path'] == str(chunk_path)

    full_chunk_path = Path('/data/loris') / chunk_path
    with (full_chunk_path / 'index.json').open() as index_file:
        chunk_index = json.load(index_file)

    assert chunk_index['chunkSize'] == 5000
    assert len(chunk_index['channelMetadata']) == 340
    assert chunk_index['shapes'][0][0] == 340
    assert (full_chunk_path / 'raw/0/0/0/0.buf').is_file()
    assert (full_chunk_path / 'raw/0/339/0/0.buf').is_file()

    head_shape_path = meg_path / 'sub-BS0001_ses-V1_headshape.pos'
    head_shape = try_get_meg_ctf_head_shape_file_with_path(db, head_shape_path)
    assert head_shape is not None
    assert file.head_shape_file_id == head_shape.id
    assert len(head_shape.points) == 255
    assert head_shape.blake2b_hash == compute_file_blake2b_hash(
        Path('/data/loris') / head_shape_path
    )

    assert_files_exist('/data/loris/bids_imports', {
        'MEG_BIDS_Brainstorm_data_sample_BIDSVersion_1.4.1': {
            'README': None,
            'dataset_description.json': None,
            'participants.tsv': None,
            'sub-BS0001': {
                'ses-V1': {
                    'sub-BS0001_ses-V1_scans.tsv': None,
                    'meg': {
                        'sub-BS0001_ses-V1_headshape.pos': None,
                        'sub-BS0001_ses-V1_task-AEF_channels.tsv': None,
                        'sub-BS0001_ses-V1_task-AEF_meg.json': None,
                        'sub-BS0001_ses-V1_task-AEF_meg.ds': {
                            'BadChannels': None,
                            'ChannelGroupSet.cfg': None,
                            'ClassFile.cls': None,
                            'MarkerFile.mrk': None,
                            'sub-BS0001_ses-V1_task-AEF_meg.acq': None,
                            'sub-BS0001_ses-V1_task-AEF_meg.eeg': None,
                            'sub-BS0001_ses-V1_task-AEF_meg.hc': None,
                            'sub-BS0001_ses-V1_task-AEF_meg.hist': None,
                            'sub-BS0001_ses-V1_task-AEF_meg.infods': None,
                            'sub-BS0001_ses-V1_task-AEF_meg.meg4': None,
                            'sub-BS0001_ses-V1_task-AEF_meg.res4': None,
                        },
                    },
                },
            },
        },
    })

    dataset = try_get_bids_dataset_with_path(db, dataset_path)
    assert dataset is not None
    # BIDS storage paths are relative to the dataset, unlike physiological file paths.
    ctf_bids_file = try_get_bids_file_with_dataset_id_path(db, dataset.id, ctf_path.relative_to(dataset_path))
    assert ctf_bids_file is not None
    assert file.bids_info_id == ctf_bids_file.id
    assert ctf_bids_file.source_path == Path('sub-BS0001/meg/sub-BS0001_task-AEF_meg.ds')
    assert not ctf_bids_file.derivative
    assert ctf_bids_file.blake2b_hash == compute_directory_blake2b_hash(
        Path('/data/loris') / ctf_path
    )

    for name in (
        'sub-BS0001_ses-V1_task-AEF_meg.json',
        'sub-BS0001_ses-V1_task-AEF_channels.tsv',
        'sub-BS0001_ses-V1_headshape.pos',
    ):
        companion_path = meg_path / name
        bids_file = try_get_bids_file_with_dataset_id_path(
            db, dataset.id, companion_path.relative_to(dataset_path)
        )
        assert bids_file is not None, str(companion_path)
        assert bids_file.source_path == Path('sub-BS0001/meg') / name.replace('_ses-V1', '')
        assert not bids_file.derivative
        assert bids_file.blake2b_hash == compute_file_blake2b_hash(Path('/data/loris') / companion_path)
        if companion_path == head_shape_path:
            assert head_shape.bids_info_id == bids_file.id


def assert_bids_dataset_registered(db: Database, dataset_path: Path):
    """
    Assert that the imported BIDS dataset and all its files are correctly registered in the BIDS
    storage tables.
    """

    dataset = try_get_bids_dataset_with_path(db, dataset_path)
    assert dataset is not None

    full_dataset_path = Path('/data/loris') / dataset_path
    for file_path in iter_all_dir_files(full_dataset_path):
        # TODO: The LORIS BIDS electrophysiology import currently creates archives in the import
        # LORIS BIDS datasets. This is undesirable as having these archives is not BIDS-compliant,
        # the pipelines should be updated to always create these archives in another directory.
        # These files are for now ignored in this test.
        if file_path.suffix == '.tgz':
            continue

        file = try_get_bids_file_with_dataset_id_path(db, dataset.id, file_path)
        assert file is not None
        assert file.blake2b_hash == compute_file_blake2b_hash(full_dataset_path / file_path)
