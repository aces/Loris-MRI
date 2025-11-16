import os
import re
import shutil
from typing import Any

from lib.config import get_data_dir_path_config, get_default_bids_visit_label_config
from lib.database import Database
from lib.db.models.session import DbSession
from lib.db.queries.candidate import try_get_candidate_with_psc_id
from lib.db.queries.session import try_get_session_with_cand_id_visit_label
from lib.eeg import Eeg
from lib.env import Env
from lib.imaging_lib.bids.dataset import BIDSDataset, BIDSDataType, BIDSSession
from lib.imaging_lib.bids.dataset_description import BidsDatasetDescriptionError
from lib.imaging_lib.bids.tsv_participants import (
    BidsTsvParticipant,
    merge_bids_tsv_participants,
    read_bids_participants_tsv_file,
    write_bids_participants_tsv_file,
)
from lib.imaging_lib.bids.tsv_scans import (
    BidsTsvScan,
    merge_bids_tsv_scans,
    read_bids_scans_tsv_file,
    write_bids_scans_tsv_file,
)
from lib.import_bids_dataset.args import Args
from lib.import_bids_dataset.check_subjects_sessions import (
    check_bids_session_labels,
    check_or_create_bids_subjects_and_sessions,
)
from lib.import_bids_dataset.env import BIDSImportEnv
from lib.import_bids_dataset.events import get_events_metadata
from lib.import_bids_dataset.mri import import_bids_nifti
from lib.import_bids_dataset.print import print_bids_import_summary
from lib.logging import log, log_error, log_error_exit, log_warning
from lib.util.iter import count

BIDS_EEG_DATA_TYPES = ['eeg', 'ieeg']

BIDS_MRI_DATA_TYPES = ['anat', 'dwi', 'fmap', 'func']


def import_bids_dataset(env: Env, args: Args, legacy_db: Database):
    """
    Read the provided BIDS dataset and import it into LORIS.
    """

    data_dir_path = get_data_dir_path_config(env)

    log(env, "Parsing BIDS dataset...")

    bids = BIDSDataset(args.source_bids_path, args.bids_validation)

    niftis_count = count(bids.niftis)

    log(env, f"Found {niftis_count} NIfTI files.")

    log(env, f"Found {len(bids.subject_labels)} subjects:")
    for subject_label in bids.subject_labels:
        log(env, f"- {subject_label}")

    log(env, f"Found {len(bids.session_labels)} sessions:")
    for session_label in bids.session_labels:
        log(env, f"- {session_label}")

    # Check the BIDS subject and session labels and create their candidates and sessions in LORIS
    # if needed.

    check_bids_session_labels(env, bids)

    project_id = check_or_create_bids_subjects_and_sessions(env, bids, args.create_candidate, args.create_session)

    # Get the LORIS BIDS import directory path and create the directory if needed.

    if args.copy:
        loris_bids_path = get_loris_bids_path(env, bids, data_dir_path)
    else:
        loris_bids_path = None

    # Get the BIDS events metadata.

    events_metadata = get_events_metadata(env, args, bids, legacy_db, loris_bids_path, project_id)

    # Copy the `participants.tsv` file rows.

    if loris_bids_path is not None and bids.tsv_participants is not None:
        loris_participants_tsv_path = os.path.join(loris_bids_path, 'participants.tsv')
        copy_bids_tsv_participants(bids.tsv_participants, loris_participants_tsv_path)

    # Process each session directory.

    import_env = BIDSImportEnv(
        data_dir_path = data_dir_path,
        loris_bids_path = loris_bids_path,
        total_files_count = niftis_count,
    )

    for bids_session in bids.sessions:
        import_bids_session(env, import_env, args, bids_session, events_metadata, legacy_db)

    # Copy the static BIDS files.

    if loris_bids_path is not None:
        copy_static_dataset_files(bids.path, loris_bids_path)

    # Print import summary.

    print_bids_import_summary(env, import_env)


def import_bids_session(
    env: Env,
    import_env: BIDSImportEnv,
    args: Args,
    bids_session: BIDSSession,
    events_metadata: dict[Any, Any],
    legacy_db: Database,
):
    """
    Read the provided BIDS session directory and import it into LORIS.
    """

    log(env, f"Importing files for subject '{bids_session.subject.label}' and session '{bids_session.label}'.")

    candidate = try_get_candidate_with_psc_id(env.db, bids_session.subject.label)
    if candidate is None:
        # This should not happen as BIDS subject labels should have been checked previously.
        log_error_exit(env, f"Candidate not found for PSCID '{bids_session.subject.label}'.")

    if bids_session.label is not None:
        visit_label = bids_session.label
    else:
        visit_label = get_default_bids_visit_label_config(env)

    session = try_get_session_with_cand_id_visit_label(env.db, candidate.cand_id, visit_label)
    if session is None:
        # This should not happen as BIDS session labels should have been checked previously.
        log_error_exit(env, f"Visit not found for visit label '{visit_label}'.")

    try:
        # Read the scans.tsv property to raise an exception if the file is incorrect.
        tsv_scans = bids_session.tsv_scans

        if import_env.loris_bids_path is not None and tsv_scans is not None:
            loris_scans_tsv_path = os.path.join(
                import_env.loris_bids_path,
                f'sub-{bids_session.subject.label}',
                f'ses-{bids_session.label}',
                f'sub-{bids_session.subject.label}_ses-{bids_session.label}_scans.tsv',
            )

            copy_bids_tsv_scans(tsv_scans, loris_scans_tsv_path)
    except Exception as exception:
        log_warning(
            env,
            f"Error while reading the session scans.tsv file, scans.tsv data will be ignored. Full error:\n{exception}"
        )

    # Process each data type directory.

    for data_type in bids_session.data_types:
        import_bids_data_type_files(env, import_env, args, session, data_type, events_metadata, legacy_db)


def import_bids_data_type_files(
    env: Env,
    import_env: BIDSImportEnv,
    args: Args,
    session: DbSession,
    data_type: BIDSDataType,
    events_metadata: dict[Any, Any],
    legacy_db: Database,
):
    """
    Read the provided BIDS data type directory and import it into LORIS.
    """

    if data_type.name in BIDS_MRI_DATA_TYPES:
        import_bids_mri_data_type_files(env, import_env, args, session, data_type)
    elif data_type.name in BIDS_EEG_DATA_TYPES:
        import_bids_eeg_data_type_files(env, import_env, args, session, data_type, events_metadata, legacy_db)
    else:
        log_warning(env, f"Unknown data type '{data_type.name}'. Skipping.")


def import_bids_mri_data_type_files(
    env: Env,
    import_env: BIDSImportEnv,
    args: Args,
    session: DbSession,
    data_type: BIDSDataType,
):
    """
    Read the BIDS MRI data type directory and import its files into LORIS.
    """

    if args.type == 'derivative':
        log_error_exit(env, "Derivative data is not support for BIDS MRI import yet.")

    if not args.copy:
        log_error_exit(env, "No copy import is not support for BIDS MRI import yet.")

    for nifti in data_type.niftis:
        try:
            import_bids_nifti(env, import_env, session, nifti)
        except Exception as exception:
            import_env.failed_files_count += 1
            log_error(
                env,
                (
                    f"Error while importing MRI file '{nifti.name}'. Error message:\n"
                    f"{exception}\n"
                    "Skipping."
                )
            )


def import_bids_eeg_data_type_files(
    env: Env,
    import_env: BIDSImportEnv,
    args: Args,
    session: DbSession,
    data_type: BIDSDataType,
    events_metadata: dict[Any, Any],
    legacy_db: Database,
):
    """
    Read the provided BIDS EEG data type directory and import it into LORIS.
    """

    loris_data_type_dir_rel_path = os.path.join(
        f'sub-{session.candidate.psc_id}',
        f'ses-{session.visit_label}',
        data_type.name,
    )

    Eeg(
        data_type              = data_type,
        db                     = legacy_db,
        verbose                = env.verbose,
        data_dir               = import_env.data_dir_path,
        session                = session,
        loris_bids_eeg_rel_dir = loris_data_type_dir_rel_path,
        loris_bids_root_dir    = import_env.loris_bids_path,
        dataset_tag_dict       = events_metadata,
        dataset_type           = args.type,
    )


def copy_bids_tsv_participants(tsv_participants: dict[str, BidsTsvParticipant], loris_participants_tsv_path: str):
    """
    Copy some participants.tsv rows into the LORIS participants.tsv file, creating it if necessary.
    """

    if os.path.exists(loris_participants_tsv_path):
        loris_tsv_participants = read_bids_participants_tsv_file(loris_participants_tsv_path)
        merge_bids_tsv_participants(tsv_participants, loris_tsv_participants)

    write_bids_participants_tsv_file(tsv_participants, loris_participants_tsv_path)


def copy_bids_tsv_scans(tsv_scans: dict[str, BidsTsvScan], loris_scans_tsv_path: str):
    """
    Copy some scans.tsv rows into a LORIS scans.tsv file, creating it if necessary.
    """

    if os.path.exists(loris_scans_tsv_path):
        loris_tsv_scans = read_bids_scans_tsv_file(loris_scans_tsv_path)
        merge_bids_tsv_scans(tsv_scans, loris_tsv_scans)

    write_bids_scans_tsv_file(tsv_scans, loris_scans_tsv_path)


def copy_static_dataset_files(source_bids_path: str, loris_bids_path: str):
    """
    Copy the static files of the source BIDS dataset to the LORIS BIDS dataset.
    """

    for file_name in ['README', 'dataset_description.json']:
        source_file_path = os.path.join(source_bids_path, file_name)
        if not os.path.isfile(source_file_path):
            continue

        loris_file_path = os.path.join(loris_bids_path, file_name)
        shutil.copyfile(source_file_path, loris_file_path)


def get_loris_bids_path(env: Env, bids: BIDSDataset, data_dir_path: str) -> str:
    """
    Get the LORIS BIDS directory path for the BIDS dataset to import, and create that directory if
    it does not exist yet.
    """

    try:
        dataset_description = bids.get_dataset_description()
    except BidsDatasetDescriptionError as error:
        log_error_exit(env, str(error))

    if dataset_description is None:
        log_error_exit(
            env,
            "No file 'dataset_description.json' found in the input BIDS dataset.",
        )

    # Sanitize the dataset metadata to have a usable name for the directory.
    dataset_name    = re.sub(r'[^0-9a-zA-Z]+',   '_', dataset_description.name)
    dataset_version = re.sub(r'[^0-9a-zA-Z\.]+', '_', dataset_description.bids_version)

    loris_bids_path = os.path.join(data_dir_path, 'bids_imports', f'{dataset_name}_BIDSVersion_{dataset_version}')

    if not os.path.exists(loris_bids_path):
        os.mkdir(loris_bids_path)

    return loris_bids_path
