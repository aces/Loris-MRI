from collections.abc import Callable
from typing import Any

from loris_bids_reader.info import BidsAcquisitionInfo
from loris_bids_reader.meg.acquisition import MegAcquisition
from loris_bids_reader.meg.reader import BidsMegDataTypeReader
from loris_bids_reader.mri.acquisition import MriAcquisition
from loris_bids_reader.mri.reader import BidsMriDataTypeReader
from loris_bids_reader.reader import BidsDatasetReader, BidsDataTypeReader, BidsSessionReader
from loris_utils.iter import count

from lib.config import get_data_dir_path_config, get_default_bids_visit_label_config
from lib.database import Database
from lib.db.models.session import DbSession
from lib.db.queries.candidate import try_get_candidate_with_psc_id
from lib.db.queries.session import try_get_session_with_cand_id_visit_label
from lib.eeg import Eeg
from lib.env import Env
from lib.import_bids_dataset.args import Args
from lib.import_bids_dataset.check_sessions import check_or_create_bids_sessions
from lib.import_bids_dataset.check_subjects import check_or_create_bids_subjects
from lib.import_bids_dataset.copy_files import (
    copy_bids_tsv_participants,
    copy_bids_tsv_scans,
    copy_static_dataset_files,
    get_loris_bids_dataset_path,
)
from lib.import_bids_dataset.env import BidsImportEnv
from lib.import_bids_dataset.events import get_root_events_metadata
from lib.import_bids_dataset.meg import import_bids_meg_acquisition
from lib.import_bids_dataset.mri import import_bids_mri_acquisition
from lib.import_bids_dataset.print import print_bids_import_summary
from lib.logging import log, log_error, log_error_exit, log_warning


def import_bids_dataset(env: Env, args: Args, legacy_db: Database):
    """
    Read the provided BIDS dataset and import it into LORIS.
    """

    data_dir_path = get_data_dir_path_config(env)

    log(env, "Parsing BIDS dataset...")

    bids = BidsDatasetReader(args.source_bids_path, args.bids_validation)

    # TODO: Not the exact count.
    acquisitions_count = count(bids.data_types)

    log(env, f"Found {acquisitions_count} acquisitions.")

    log(env, f"Found {len(bids.subject_labels)} subjects:")
    for subject_label in bids.subject_labels:
        log(env, f"- {subject_label}")

    log(env, f"Found {len(bids.session_labels)} sessions:")
    for session_label in bids.session_labels:
        log(env, f"- {session_label}")

    # Check the BIDS subject and session labels and create their candidates and sessions in LORIS
    # if needed.

    check_or_create_bids_subjects(
        env,
        [subject.info for subject in bids.subjects],
        args.create_candidate,
    )

    sessions = check_or_create_bids_sessions(
        env,
        [session.info for session in bids.sessions],
        args.create_session,
    )

    project_id = sessions[0].project.id

    env.db.commit()

    # Get the LORIS BIDS import directory path and create the directory if needed.

    if args.copy:
        loris_bids_path = get_loris_bids_dataset_path(env, bids, data_dir_path)
    else:
        loris_bids_path = None

    # Get the BIDS events metadata.

    events_metadata = get_root_events_metadata(env, args, bids, loris_bids_path, project_id)

    # Copy the `participants.tsv` file rows.

    if loris_bids_path is not None and bids.participants_file is not None:
        loris_participants_tsv_path = loris_bids_path / 'participants.tsv'
        copy_bids_tsv_participants(bids.participants_file, loris_participants_tsv_path)

    # Process each session directory.

    import_env = BidsImportEnv(
        data_dir_path     = data_dir_path,
        loris_bids_path   = loris_bids_path,
        total_files_count = acquisitions_count,
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
    import_env: BidsImportEnv,
    args: Args,
    bids_session: BidsSessionReader,
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
        if visit_label is None:
            log_error_exit(
                env,
                "Missing BIDS session in the dataset or default BIDS visit label in the LORIS configuration.",
            )

    session = try_get_session_with_cand_id_visit_label(env.db, candidate.cand_id, visit_label)
    if session is None:
        # This should not happen as BIDS session labels should have been checked previously.
        log_error_exit(env, f"Visit not found for visit label '{visit_label}'.")

    try:
        # Read the scans.tsv property to raise an exception if the file is incorrect.
        scans_file = bids_session.scans_file

        if import_env.loris_bids_path is not None and scans_file is not None:
            loris_scans_tsv_path = (
                import_env.loris_bids_path
                / f'sub-{bids_session.subject.label}'
                / f'ses-{bids_session.label}'
                / f'sub-{bids_session.subject.label}_ses-{bids_session.label}_scans.tsv'
            )

            copy_bids_tsv_scans(scans_file, loris_scans_tsv_path)
    except Exception as exception:
        log_warning(
            env,
            f"Error while reading the session scans.tsv file, scans.tsv data will be ignored. Full error:\n{exception}"
        )

    # Process each data type directory.

    for data_type in bids_session.data_types:
        import_bids_data_type(env, import_env, args, session, data_type, events_metadata, legacy_db)


def import_bids_data_type(
    env: Env,
    import_env: BidsImportEnv,
    args: Args,
    session: DbSession,
    data_type: BidsDataTypeReader,
    events_metadata: dict[Any, Any],
    legacy_db: Database,
):
    """
    Read the provided BIDS data type directory and import it into LORIS.
    """

    match data_type:
        case BidsMriDataTypeReader() | BidsMegDataTypeReader():
            import_bids_data_type_acquisitions(
                env,
                import_env,
                data_type,
                lambda acquisition, bids_info:
                    import_bids_acquisition(env, import_env, args, session, acquisition, bids_info),
            )
        case BidsDataTypeReader():
            import_bids_eeg_data_type_files(env, import_env, args, session, data_type, events_metadata, legacy_db)


def import_bids_data_type_acquisitions(
    env: Env,
    import_env: BidsImportEnv,
    data_type: BidsMegDataTypeReader | BidsMriDataTypeReader,
    import_acquisition: Callable[[Any, BidsAcquisitionInfo], None],
):
    """
    Read the BIDS MRI data type directory and import its files into LORIS.
    Read a BIDS data type directory and import its acquisitions into LORIS.
    """

    log(env, f"Importing data type {data_type.name}")

    if data_type.session.scans_file is None:
        log_warning(env, "No 'scans.tsv' file found, 'scans.tsv' data will be ignored.")

    for acquisition, bids_info in data_type.acquisitions:
        try:
            import_acquisition(acquisition, bids_info)
        except Exception as exception:
            import_env.failed_files_count += 1
            log_error(
                env,
                (
                    f"Error while importing acquisition '{bids_info.name}'. Error message:\n"
                    f"{exception}\n"
                    "Skipping."
                )
            )
            import traceback
            print(traceback.format_exc())


def import_bids_acquisition(
    env: Env,
    import_env: BidsImportEnv,
    args: Args,
    session: DbSession,
    acquisition: Any,
    bids_info: BidsAcquisitionInfo,
):
    """
    Import a BIDS acquisition and its associated files in LORIS.
    """

    log(
        env,
        (
            f"Importing {acquisition.data_type.name} acquisition '{acquisition.name}'..."
            f" ({import_env.processed_files_count + 1} / {import_env.total_files_count})"
        ),
    )

    # Get the path at which to copy the file.

    match acquisition:
        case MriAcquisition():
            import_bids_mri_acquisition(env, import_env, session, acquisition, bids_info)
        case MegAcquisition():
            import_bids_meg_acquisition(env, import_env, args, session, acquisition, bids_info)
        case _:
            log_warning(env, f"Unknown acquisition type '{bids_info.name}'. Skipping.")

    print(f"Successfully imported acquisition '{bids_info.name}'.")


def import_bids_eeg_data_type_files(
    env: Env,
    import_env: BidsImportEnv,
    args: Args,
    session: DbSession,
    data_type: BidsDataTypeReader,
    events_metadata: dict[Any, Any],
    legacy_db: Database,
):
    """
    Read the provided BIDS EEG data type directory and import it into LORIS.
    """

    Eeg(
        env                    = env,
        import_env             = import_env,
        bids_layout            = data_type.session.subject.dataset.layout,
        bids_info              = data_type.info,
        db                     = legacy_db,
        session                = session,
        dataset_tag_dict       = events_metadata,
        dataset_type           = args.type,
    )
