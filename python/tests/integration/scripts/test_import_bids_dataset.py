import json
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

from loris_utils.crypto import compute_path_blake2b_hash
from sqlalchemy.orm import Session as Database

from lib.db.queries.bids_dataset import try_get_bids_dataset_with_path
from lib.db.queries.bids_event_dataset_mapping import get_bids_event_dataset_mappings_with_project_id
from lib.db.queries.bids_file import get_bids_files_with_dataset_id, try_get_bids_file_with_dataset_id_path
from lib.db.queries.candidate import try_get_candidate_with_psc_id
from lib.db.queries.config import set_config_with_setting_name
from lib.db.queries.meg_ctf_head_shape import try_get_meg_ctf_head_shape_file_with_path
from lib.db.queries.physio_file import try_get_physio_file_with_path
from lib.db.queries.session import try_get_session_with_cand_id_visit_label
from lib.physio.parameters import get_physio_file_parameters_dict
from tests.util.database import get_integration_database_session
from tests.util.file_system import assert_files_exist
from tests.util.run_integration_script import run_integration_script


@dataclass(frozen=True)
class BidsFileData:
    path: Path
    source_path: Path | None
    suffix: str | None
    extension: str | None
    entities: dict[str, str]
    blake2b_hash: str
    derivative: bool


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
        [
            BidsFileData(
                path         = Path('README'),
                source_path  = Path('README'),
                suffix       = None,
                extension    = None,
                entities     = {},
                blake2b_hash = '5bad6701fe332b38f01d92665a73e08535c6048aee3efbdc4fff5378a2d04e5cf512862db08e918d52df06595eb7d43ee1c2faf920a39dfc4509e6d851ccc242',  # ruff: ignore[line-too-long]
                derivative   = False,
            ),
            BidsFileData(
                path         = Path('dataset_description.json'),
                source_path  = Path('dataset_description.json'),
                suffix       = None,
                extension    = 'json',
                entities     = {},
                blake2b_hash = '1d49c3e80a29ef17e09845e385bad2ac9b00a418f4b4f1949a3fba0c29531c08b3c6abb04e4050464eb6961d18dcfd0eab0d286766b0b2d6427a0055e7823247',  # ruff: ignore[line-too-long]
                derivative   = False,
            ),
            BidsFileData(
                path         = Path('events.json'),
                source_path  = Path('events.json'),
                suffix       = 'events',
                extension    = 'json',
                entities     = {},
                blake2b_hash = 'ec13d026a5c00320828be66673829e2c079ad0572ea8632e1d79cd53db99686e6744105584710cc14aacaf53d19a38907f6db4f00c18f1917009222640551531',  # ruff: ignore[line-too-long]
                derivative   = False,
            ),
            BidsFileData(
                path         = Path('participants.tsv'),
                source_path  = Path('participants.tsv'),
                suffix       = 'participants',
                extension    = 'tsv',
                entities     = {},
                blake2b_hash = 'fe4c81240410683852e08156fe3d1c6422372bd441a754e5429adfbe4ef56ccf5ef5352b4864bcf29f2bd1c1ac9998d6107e57a44ef9f94e3c7546f615dab876',  # ruff: ignore[line-too-long]
                derivative   = False,
            ),
            BidsFileData(
                path         = Path('sub-OTT166/ses-V1/eeg/sub-OTT166_ses-V1_task-faceO_channels.tsv'),
                source_path  = Path('sub-OTT166/ses-V1/eeg/sub-OTT166_ses-V1_task-faceO_channels.tsv'),
                suffix       = 'channels',
                extension    = 'tsv',
                entities     = {'sub': 'OTT166', 'ses': 'V1', 'task': 'faceO'},
                blake2b_hash = '7b91e3650086ef50ecc00f1c50e17e7ad8dc39c484536bbc2423af4be7d2b50a3a0010f840d457fec68fbfb3e136edf4d616a31bab0ca09ed686f555727341dd',  # ruff: ignore[line-too-long]
                derivative   = False,
            ),
            BidsFileData(
                path         = Path('sub-OTT166/ses-V1/eeg/sub-OTT166_ses-V1_task-faceO_eeg.edf'),
                source_path  = Path('sub-OTT166/ses-V1/eeg/sub-OTT166_ses-V1_task-faceO_eeg.edf'),
                suffix       = 'eeg',
                extension    = 'edf',
                entities     = {'sub': 'OTT166', 'ses': 'V1', 'task': 'faceO'},
                blake2b_hash = '8c24c5907b724d659f38c65bfffc754003a586961ea9e25ed5fa0741a2691ed217e29553020230553c84c0b5978edf64624747d31623f6267cbd36eba8b70891',  # ruff: ignore[line-too-long]
                derivative   = False,
            ),
            BidsFileData(
                path         = Path('sub-OTT166/ses-V1/eeg/sub-OTT166_ses-V1_task-faceO_eeg.json'),
                source_path  = Path('sub-OTT166/ses-V1/eeg/sub-OTT166_ses-V1_task-faceO_eeg.json'),
                suffix       = 'eeg',
                extension    = 'json',
                entities     = {'sub': 'OTT166', 'ses': 'V1', 'task': 'faceO'},
                blake2b_hash = 'f762bbf2e4699fbe47a53f2b7c2f990dc401d7aa57a6b4ba37aa04acdc2748feb42ee058b874a14fae7c14f673280847e40a60771b3c397a0cf5abdb8c05077a',  # ruff: ignore[line-too-long]
                derivative   = False,
            ),
            BidsFileData(
                path         = Path('sub-OTT166/ses-V1/eeg/sub-OTT166_ses-V1_task-faceO_electrodes.tsv'),
                source_path  = Path('sub-OTT166/ses-V1/eeg/sub-OTT166_ses-V1_task-faceO_electrodes.tsv'),
                suffix       = 'electrodes',
                extension    = 'tsv',
                entities     = {'sub': 'OTT166', 'ses': 'V1', 'task': 'faceO'},
                blake2b_hash = '0206db2650ae5a07e4225ff87b6fb2a6bfcf6ea088dd8cdfd77d04e9e25a171ffe68878aa156478babb32dcaf9b46459f87fe0516b728278cc0d9372a0d49299',  # ruff: ignore[line-too-long]
                derivative   = False,
            ),
            BidsFileData(
                path         = Path('sub-OTT166/ses-V1/eeg/sub-OTT166_ses-V1_task-faceO_events.tsv'),
                source_path  = Path('sub-OTT166/ses-V1/eeg/sub-OTT166_ses-V1_task-faceO_events.tsv'),
                suffix       = 'events',
                extension    = 'tsv',
                entities     = {'sub': 'OTT166', 'ses': 'V1', 'task': 'faceO'},
                blake2b_hash = '532aa0b52749eb9ee52c2bbb65fa7b1d00d7126cb9a4e10bd4b9dbb4c5527b06e30acdaf17d5806e81d3ce8ad224a9f456e27aba1bf8b92fd43522837c7ffec7',  # ruff: ignore[line-too-long]
                derivative   = False,
            ),
            BidsFileData(
                path         = Path('sub-OTT166/ses-V1/sub-OTT166_ses-V1_scans.tsv'),
                source_path  = Path('sub-OTT166/ses-V1/sub-OTT166_ses-V1_scans.tsv'),
                suffix       = 'scans',
                extension    = 'tsv',
                entities     = {'sub': 'OTT166', 'ses': 'V1'},
                blake2b_hash = 'e35a1749f715c8acd29fd22e76d6bd1516b9e85435a537f1759717f92baf58f062069f05676b7ce86b7b742d0cece4a1ea575fcd1fd68127eb5f6fa398b231d5',  # ruff: ignore[line-too-long]
                derivative   = False,
            ),
        ],
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
        [
            BidsFileData(
                path         = Path('dataset_description.json'),
                source_path  = Path('dataset_description.json'),
                suffix       = None,
                extension    = 'json',
                entities     = {},
                blake2b_hash = 'd89fbe005d51cbbee368735d47efdf1bcbe96314e6ced638e9d8532f7e0a1041d6c74e901c22d695f57139b80c9de62881b61a73f8a2ea6f8717304c49f29e40',  # ruff: ignore[line-too-long]
                derivative   = False,
            ),
            BidsFileData(
                path         = Path('participants.tsv'),
                source_path  = Path('participants.tsv'),
                suffix       = 'participants',
                extension    = 'tsv',
                entities     = {},
                blake2b_hash = '7b8531f8cd6f30b041635ca2d63ec9e2f07e2fb5d144cf790e20e784bb5e2af38873aace8029a65513c135f8f1e465a6f9ba789baacc2b1fe6e665ffe72d2394',  # ruff: ignore[line-too-long]
                derivative   = False,
            ),
            BidsFileData(
                path         = Path('sub-DCC090/ses-V2/anat/sub-DCC090_ses-V2_acq-spc3p2_run-4_T2w.json'),
                source_path  = Path('sub-DCC090/ses-V2/anat/sub-DCC090_ses-V2_acq-spc3p2_run-4_T2w.json'),
                suffix       = 'T2w',
                extension    = 'json',
                entities     = {'sub': 'DCC090', 'ses': 'V2', 'acq': 'spc3p2', 'run': '4'},
                blake2b_hash = 'dc6744e5f8e343f00408382e9d5d393bab00ad5e94a589cd2788e96ce783bee106e6dd13c2f941bf09754e8f22629fad6805ac58c73ad8d0846d070d47a35611',  # ruff: ignore[line-too-long]
                derivative   = False,
            ),
            BidsFileData(
                path         = Path('sub-DCC090/ses-V2/anat/sub-DCC090_ses-V2_acq-spc3p2_run-4_T2w.nii.gz'),
                source_path  = Path('sub-DCC090/ses-V2/anat/sub-DCC090_ses-V2_acq-spc3p2_run-4_T2w.nii.gz'),
                suffix       = 'T2w',
                extension    = 'nii.gz',
                entities     = {'sub': 'DCC090', 'ses': 'V2', 'acq': 'spc3p2', 'run': '4'},
                blake2b_hash = '41b6a3caade80a8ce4b302cc8da5c92d9d805a0801abeb9cc0c30d3017670fe7b1a0358f43fcd6678220c741874413908a765c62859f726ee12f94711eb97dbd',  # ruff: ignore[line-too-long]
                derivative   = False,
            ),
            BidsFileData(
                path         = Path('sub-DCC090/ses-V2/anat/sub-DCC090_ses-V2_acq-tfl3p2_run-3_T1w.json'),
                source_path  = Path('sub-DCC090/ses-V2/anat/sub-DCC090_ses-V2_acq-tfl3p2_run-3_T1w.json'),
                suffix       = 'T1w',
                extension    = 'json',
                entities     = {'sub': 'DCC090', 'ses': 'V2', 'acq': 'tfl3p2', 'run': '3'},
                blake2b_hash = 'c96dfa12308a9d40a069a95211b808a4e8571e78293d5c2da94b7837926f90edd5a64ef3bbb494deef9ebf751f5628e9ff9ed58936467cde6a76ac8485b12155',  # ruff: ignore[line-too-long]
                derivative   = False,
            ),
            BidsFileData(
                path         = Path('sub-DCC090/ses-V2/anat/sub-DCC090_ses-V2_acq-tfl3p2_run-3_T1w.nii.gz'),
                source_path  = Path('sub-DCC090/ses-V2/anat/sub-DCC090_ses-V2_acq-tfl3p2_run-3_T1w.nii.gz'),
                suffix       = 'T1w',
                extension    = 'nii.gz',
                entities     = {'sub': 'DCC090', 'ses': 'V2', 'acq': 'tfl3p2', 'run': '3'},
                blake2b_hash = 'cc1a25395ec75dc7399c1d2be53e00bdbcefb94e7f11a03006fa245e416d0886c3c36c35afe1a08bd320e6218b62967408364f03076312f07f10c398437bafe6',  # ruff: ignore[line-too-long]
                derivative   = False,
            ),
            BidsFileData(
                path         = Path('sub-DCC090/ses-V2/anat/sub-DCC090_ses-V2_acq-tse2p2_run-2_echo-1_T2w.json'),
                source_path  = Path('sub-DCC090/ses-V2/anat/sub-DCC090_ses-V2_acq-tse2p2_run-2_echo-1_T2w.json'),
                suffix       = 'T2w',
                extension    = 'json',
                entities     = {'sub': 'DCC090', 'ses': 'V2', 'acq': 'tse2p2', 'run': '2', 'echo': '1'},
                blake2b_hash = '6094f96f940c782c41306effd90b52ba9af9acdedb5c8a5f44a6efbbe29676fd4acd872e997b401647283ad4dc12356362ff381e11dbf52435f4af1f8f1dfa17',  # ruff: ignore[line-too-long]
                derivative   = False,
            ),
            BidsFileData(
                path         = Path('sub-DCC090/ses-V2/anat/sub-DCC090_ses-V2_acq-tse2p2_run-2_echo-1_T2w.nii.gz'),
                source_path  = Path('sub-DCC090/ses-V2/anat/sub-DCC090_ses-V2_acq-tse2p2_run-2_echo-1_T2w.nii.gz'),
                suffix       = 'T2w',
                extension    = 'nii.gz',
                entities     = {'sub': 'DCC090', 'ses': 'V2', 'acq': 'tse2p2', 'run': '2', 'echo': '1'},
                blake2b_hash = '6af226efbc3e2b38115ccac70cd34c97f900e663ec2138492a11165d420e4033a28b5972998950a03d6afea18092db245bed9106647be984051ed0a03219c051',  # ruff: ignore[line-too-long]
                derivative   = False,
            ),
            BidsFileData(
                path         = Path('sub-DCC090/ses-V2/anat/sub-DCC090_ses-V2_acq-tse2p2_run-2_echo-2_T2w.json'),
                source_path  = Path('sub-DCC090/ses-V2/anat/sub-DCC090_ses-V2_acq-tse2p2_run-2_echo-2_T2w.json'),
                suffix       = 'T2w',
                extension    = 'json',
                entities     = {'sub': 'DCC090', 'ses': 'V2', 'acq': 'tse2p2', 'run': '2', 'echo': '2'},
                blake2b_hash = '70d54c0ae66a30b05fdfcd5f56e72f3fcb326bcf3fd5ec271dab2b7a9f76218320ced5b9d7d27ebf84b3f8526362a854dda14d47d244af1f2e4414d3ea2dc518',  # ruff: ignore[line-too-long]
                derivative   = False,
            ),
            BidsFileData(
                path         = Path('sub-DCC090/ses-V2/anat/sub-DCC090_ses-V2_acq-tse2p2_run-2_echo-2_T2w.nii.gz'),
                source_path  = Path('sub-DCC090/ses-V2/anat/sub-DCC090_ses-V2_acq-tse2p2_run-2_echo-2_T2w.nii.gz'),
                suffix       = 'T2w',
                extension    = 'nii.gz',
                entities     = {'sub': 'DCC090', 'ses': 'V2', 'acq': 'tse2p2', 'run': '2', 'echo': '2'},
                blake2b_hash = '6a375c9fbfb528bf3b6377fcea2df07e85158eb73fb41bb879269a1694697b31184e21abae9702ba9b7f6be82dfc068ea08c27c38392c65096b22b0063b43402',  # ruff: ignore[line-too-long]
                derivative   = False,
            ),
            BidsFileData(
                path         = Path('sub-DCC090/ses-V2/dwi/sub-DCC090_ses-V2_acq-epb0_dir-AP_run-5_dwi.bval'),
                source_path  = Path('sub-DCC090/ses-V2/dwi/sub-DCC090_ses-V2_acq-epb0_dir-AP_run-5_dwi.bval'),
                suffix       = 'dwi',
                extension    = 'bval',
                entities     = {'sub': 'DCC090', 'ses': 'V2', 'acq': 'epb0', 'dir': 'AP', 'run': '5'},
                blake2b_hash = '9841f35109880be5621b4c70c919b259f8df13d7f915aeaab203dde6b4007bfb6138749d9bf834c3c3cb55a0f6b133a887bafb46dadcae22cec87c0fc6d64107',  # ruff: ignore[line-too-long]
                derivative   = False,
            ),
            BidsFileData(
                path         = Path('sub-DCC090/ses-V2/dwi/sub-DCC090_ses-V2_acq-epb0_dir-AP_run-5_dwi.bvec'),
                source_path  = Path('sub-DCC090/ses-V2/dwi/sub-DCC090_ses-V2_acq-epb0_dir-AP_run-5_dwi.bvec'),
                suffix       = 'dwi',
                extension    = 'bvec',
                entities     = {'sub': 'DCC090', 'ses': 'V2', 'acq': 'epb0', 'dir': 'AP', 'run': '5'},
                blake2b_hash = 'b993e5f8d9b451f51b21273c19e5cfd388b03917bd12a157eb394a3513cf416ad996544b47f51cf7c2b5c1f2fafe5d243aecc9338a79256543030c0b79809d05',  # ruff: ignore[line-too-long]
                derivative   = False,
            ),
            BidsFileData(
                path         = Path('sub-DCC090/ses-V2/dwi/sub-DCC090_ses-V2_acq-epb0_dir-AP_run-5_dwi.json'),
                source_path  = Path('sub-DCC090/ses-V2/dwi/sub-DCC090_ses-V2_acq-epb0_dir-AP_run-5_dwi.json'),
                suffix       = 'dwi',
                extension    = 'json',
                entities     = {'sub': 'DCC090', 'ses': 'V2', 'acq': 'epb0', 'dir': 'AP', 'run': '5'},
                blake2b_hash = '03ccff54d0d91afab42d59ef9823b1a3f6c0086a2151ca131796e58c1039a7ca5d426a74e13400bf803263652880f104268abc37ab153fa63ae8d9660142454f',  # ruff: ignore[line-too-long]
                derivative   = False,
            ),
            BidsFileData(
                path         = Path('sub-DCC090/ses-V2/dwi/sub-DCC090_ses-V2_acq-epb0_dir-AP_run-5_dwi.nii.gz'),
                source_path  = Path('sub-DCC090/ses-V2/dwi/sub-DCC090_ses-V2_acq-epb0_dir-AP_run-5_dwi.nii.gz'),
                suffix       = 'dwi',
                extension    = 'nii.gz',
                entities     = {'sub': 'DCC090', 'ses': 'V2', 'acq': 'epb0', 'dir': 'AP', 'run': '5'},
                blake2b_hash = '57114f7b4b536b5dfb2b0453cffc49f1952857aa35fa41651024ee0b99a84d7670287d15229ee76c2f6f6429aae9ba470db343040f0468d8ad1413ddd6d905de',  # ruff: ignore[line-too-long]
                derivative   = False,
            ),
        ],
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
    assert head_shape.blake2b_hash == 'e75b2f6d0de172363daaa8bd128fb6a9a760051a3c5aa66199958494c50a8d0474578b8be5a0d3c3bd4f24dd827cdb79e86453b1433f01b10df0d00d4e8d8363'  # ruff: ignore[line-too-long]

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
    head_shape_bids_file = try_get_bids_file_with_dataset_id_path(
        db, dataset.id, head_shape_path.relative_to(dataset_path),
    )
    assert head_shape_bids_file is not None
    assert head_shape.bids_info_id == head_shape_bids_file.id

    assert_bids_dataset_registered(
        db,
        dataset_path,
        [
            BidsFileData(
                path         = Path('README'),
                source_path  = Path('README'),
                suffix       = None,
                extension    = None,
                entities     = {},
                blake2b_hash = '5b4a53de2c8d9b2bf058329982c00772a919909f193f2eadaab09da98fd490e7ca15a032e22f860e8e35cbd28199ef07e1a11b8e05bc2ebcb7a59d1844f1bc0d',  # ruff: ignore[line-too-long]
                derivative   = False,
            ),
            BidsFileData(
                path         = Path('dataset_description.json'),
                source_path  = Path('dataset_description.json'),
                suffix       = None,
                extension    = 'json',
                entities     = {},
                blake2b_hash = '456dd3638366b987f8b57ad212a3b8956fd99b26c0cb3460f57dd9c4cd6f3ffc96f53977553812b4d6182d0ac9a5726d54b39c24c986e0a9f43b0987a0e9416f',  # ruff: ignore[line-too-long]
                derivative   = False,
            ),
            BidsFileData(
                path         = Path('participants.tsv'),
                source_path  = Path('participants.tsv'),
                suffix       = 'participants',
                extension    = 'tsv',
                entities     = {},
                blake2b_hash = '63712da8532e69fbff197335903122ebc4c7e7cefb075726f82641ab57663bebd1de3391b6b34615733f578406ae2dcc4e2c2cd640e5112a3ce1abb6a588b5f9',  # ruff: ignore[line-too-long]
                derivative   = False,
            ),
            BidsFileData(
                path         = Path('sub-BS0001/ses-V1/anat/sub-BS0001_ses-V1_T1w.nii.gz'),
                source_path  = Path('sub-BS0001/anat/sub-BS0001_T1w.nii.gz'),
                suffix       = 'T1w',
                extension    = 'nii.gz',
                entities     = {'sub': 'BS0001', 'ses': 'V1'},
                blake2b_hash = '23a4417b0019fc1d43d294b40443ff9bbe8943d14f0a79058127753ae1d0862732045685413ec5017546eeb28634244d9df5cafce1ae93e71473f067a04d2766',  # ruff: ignore[line-too-long]
                derivative   = False,
            ),
            BidsFileData(
                path         = Path('sub-BS0001/ses-V1/meg/sub-BS0001_ses-V1_headshape.pos'),
                source_path  = Path('sub-BS0001/meg/sub-BS0001_headshape.pos'),
                suffix       = 'headshape',
                extension    = 'pos',
                entities     = {'sub': 'BS0001', 'ses': 'V1'},
                blake2b_hash = 'e75b2f6d0de172363daaa8bd128fb6a9a760051a3c5aa66199958494c50a8d0474578b8be5a0d3c3bd4f24dd827cdb79e86453b1433f01b10df0d00d4e8d8363',  # ruff: ignore[line-too-long]
                derivative   = False,
            ),
            BidsFileData(
                path         = Path('sub-BS0001/ses-V1/meg/sub-BS0001_ses-V1_task-AEF_channels.tsv'),
                source_path  = Path('sub-BS0001/meg/sub-BS0001_task-AEF_channels.tsv'),
                suffix       = 'channels',
                extension    = 'tsv',
                entities     = {'sub': 'BS0001', 'ses': 'V1', 'task': 'AEF'},
                blake2b_hash = '9b294f17ea6497d58f91ff303ddafec3e643d415718ac04b0dcfe5f6e6c7355f06005ee876d9ad374eee6ca5416e3b957fb6baebd3caebd806c9477475c66222',  # ruff: ignore[line-too-long]
                derivative   = False,
            ),
            BidsFileData(
                path         = Path('sub-BS0001/ses-V1/meg/sub-BS0001_ses-V1_task-AEF_meg.ds'),
                source_path  = Path('sub-BS0001/meg/sub-BS0001_task-AEF_meg.ds'),
                suffix       = 'meg',
                extension    = 'ds',
                entities     = {'sub': 'BS0001', 'ses': 'V1', 'task': 'AEF'},
                blake2b_hash = '4e0bea92b22443a0f4d72a4bcd5f639e8d9281453304ca952e24915749991769edf4fa716feeb6036d086e6aeae2c9df1c03fe3f483564a676b1763f7226e403',  # ruff: ignore[line-too-long]
                derivative   = False,
            ),
            BidsFileData(
                path         = Path('sub-BS0001/ses-V1/meg/sub-BS0001_ses-V1_task-AEF_meg.json'),
                source_path  = Path('sub-BS0001/meg/sub-BS0001_task-AEF_meg.json'),
                suffix       = 'meg',
                extension    = 'json',
                entities     = {'sub': 'BS0001', 'ses': 'V1', 'task': 'AEF'},
                blake2b_hash = '8b08f780f93baf21b548ee42c50ce384f7abb48d1ce67b3a957ae6e2103a7f1894c2cca037cf76a55de1cb02929fda1ad3d89d1fa320c811c5aa5d989d05659a',  # ruff: ignore[line-too-long]
                derivative   = False,
            ),
            BidsFileData(
                path         = Path('sub-BS0001/ses-V1/sub-BS0001_ses-V1_scans.tsv'),
                source_path  = Path('sub-BS0001/sub-BS0001_scans.tsv'),
                suffix       = 'scans',
                extension    = 'tsv',
                entities     = {'sub': 'BS0001', 'ses': 'V1'},
                blake2b_hash = 'cf6b7d0acee8f48ddaf1f0dfc16968cc110d98f8a288e3c229644e711f9c234aa50c094f35e17acc301a0a6d65cf37b0b94d1812a0b8d82cc729541e59fa6ad8',  # ruff: ignore[line-too-long]
                derivative   = False,
            ),
        ],
    )


def assert_bids_dataset_registered(db: Database, dataset_path: Path, expected: list[BidsFileData]):
    """
    Compare every BIDS file row with fixed expectations for the CI imaging fixtures.
    """

    dataset = try_get_bids_dataset_with_path(db, dataset_path)
    assert dataset is not None

    files = get_bids_files_with_dataset_id(db, dataset.id)
    actual = [
        BidsFileData(
            path         = file.path,
            source_path  = file.source_path,
            suffix       = file.suffix,
            extension    = file.extension,
            entities     = {entity.key: entity.value for entity in file.entities},
            blake2b_hash = file.blake2b_hash,
            derivative   = file.derivative,
        )
        for file in files
    ]

    assert sorted(actual, key=lambda file: file.path) == sorted(expected, key=lambda file: file.path)

    # Check the copied contents against the same fixed hashes, including CTF directory contents.
    for file in expected:
        full_path = Path('/data/loris') / dataset_path / file.path
        assert compute_path_blake2b_hash(full_path) == file.blake2b_hash, str(file.path)
