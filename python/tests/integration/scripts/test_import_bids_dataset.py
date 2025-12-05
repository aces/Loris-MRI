from lib.db.queries.candidate import try_get_candidate_with_psc_id
from lib.db.queries.config import set_config_with_setting_name
from lib.db.queries.physio_file import try_get_physio_file_with_path
from lib.db.queries.session import try_get_session_with_cand_id_visit_label
from lib.imaging_lib.physio import get_physio_file_parameters_dict
from tests.util.database import get_integration_database_session
from tests.util.file_system import assert_files_exist
from tests.util.run_integration_script import run_integration_script


def test_import_eeg_bids_dataset():
    db = get_integration_database_session()

    # Enable EEG chunking.
    set_config_with_setting_name(db, 'useEEGBrowserVisualizationComponents', 'true')
    db.commit()

    process = run_integration_script([
        'bids_import.py',
        '--createcandidate', '--createsession',
        '--directory', '/data/loris/incoming/Face13',
    ])

    # Check the return code.
    assert process.returncode == 0

    # Check that the candidate and sessions are present in the database.
    candidate = try_get_candidate_with_psc_id(db, 'OTT166')
    assert candidate is not None
    session = try_get_session_with_cand_id_visit_label(db, candidate.cand_id, 'V1')
    assert session is not None

    # Check that the physiological file has been inserted in the database.
    file = try_get_physio_file_with_path(
        db,
        'bids_imports/Face13_BIDSVersion_1.1.0/sub-OTT166/ses-V1/eeg/sub-OTT166_ses-V1_task-faceO_eeg.edf',
    )
    assert file is not None

    # Check that the physiological file parameters has been inserted in the database.
    file_parameters = get_physio_file_parameters_dict(db, file.id)
    assert file_parameters == {
        'TaskName': 'FaceHouseCheck',
        'TaskDescription': 'Visual presentation of oval cropped face and house images both upright and inverted. Rare left or right half oval checkerboards were presetned as targets for keypress response.',  # noqa: E501
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
        'EEGPlacementScheme': 'Custom equidistant 128 channel BioSemi montage established in coordination with Judith Schedden McMaster Univertisy',  # noqa: E501
        'Manufacturer': 'BioSemi',
        'CapManufacturer': 'ElectroCap International',
        'HardwareFilters': 'n/a',
        'SoftwareFilters': 'n/a',
        'RecordingType': 'continuous',
        'RecordingDuration': '1119',
        'eegjson_file': 'bids_imports/Face13_BIDSVersion_1.1.0/sub-OTT166/ses-V1/eeg/sub-OTT166_ses-V1_task-faceO_eeg.json',  # noqa: E501
        'physiological_json_file_blake2b_hash': 'f762bbf2e4699fbe47a53f2b7c2f990dc401d7aa57a6b4ba37aa04acdc2748feb42ee058b874a14fae7c14f673280847e40a60771b3c397a0cf5abdb8c05077a',  # noqa: E501
        'physiological_file_blake2b_hash': '8c24c5907b724d659f38c65bfffc754003a586961ea9e25ed5fa0741a2691ed217e29553020230553c84c0b5978edf64624747d31623f6267cbd36eba8b70891',  # noqa: E501
        'electrode_file_blake2b_hash': '0206db2650ae5a07e4225ff87b6fb2a6bfcf6ea088dd8cdfd77d04e9e25a171ffe68878aa156478babb32dcaf9b46459f87fe0516b728278cc0d9372a0d49299',  # noqa: E501
        'channel_file_blake2b_hash': '7b91e3650086ef50ecc00f1c50e17e7ad8dc39c484536bbc2423af4be7d2b50a3a0010f840d457fec68fbfb3e136edf4d616a31bab0ca09ed686f555727341dd',  # noqa: E501
        'event_file_blake2b_hash': '532aa0b52749eb9ee52c2bbb65fa7b1d00d7126cb9a4e10bd4b9dbb4c5527b06e30acdaf17d5806e81d3ce8ad224a9f456e27aba1bf8b92fd43522837c7ffec7',  # noqa: E501
        'electrophysiology_chunked_dataset_path': 'bids_imports/Face13_BIDSVersion_1.1.0_chunks/sub-OTT166_ses-V1_task-faceO_eeg.chunks',  # noqa: E501
    }

    # Check that the BIDS files have been copied.
    assert_files_exist('/data/loris/bids_imports', {
        'Face13_BIDSVersion_1.1.0': {
            'dataset_description.json': None,
            'participants.tsv': None,
            'README': None,
            'sub-OTT166': {
                'ses-V1': {
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

    # Check that the chunk files have been created.
    assert_files_exist('/data/loris/bids_imports', {
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
