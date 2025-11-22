from lib.db.queries.candidate import try_get_candidate_with_psc_id
from lib.db.queries.config import set_config_with_setting_name
from lib.db.queries.session import try_get_session_with_cand_id_visit_label
from tests.util.database import get_integration_database_session
from tests.util.file_system import check_file_tree
from tests.util.run_integration_script import run_integration_script


def test_import_eeg_bids_dataset():
    db = get_integration_database_session()

    # Enable EEG chunking.
    set_config_with_setting_name(db, 'useEEGBrowserVisualizationComponents', 'true')
    db.commit()

    process = run_integration_script([
        'import_bids_dataset.py',
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

    # TODO: Add EEG-specific database checks once the EEG-specific ORM models have been created.

    # Check that the BIDS files have been copied.
    assert check_file_tree('/data/loris/bids_imports/', {
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
    assert check_file_tree('/data/loris/bids_imports/', {
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
