import os
from collections.abc import Callable
from typing import Any

from loris_bids_reader.dataset import BidsAcquisition, BIDSDataset, BidsDataType, BIDSSession
from loris_bids_reader.eeg.data_type import BidsEegDataType
from loris_bids_reader.meg.data_type import BidsMegAcquisition, BidsMegDataType
from loris_bids_reader.mri.data_type import BidsMriAcquisition, BidsMriDataType

from lib.config import get_data_dir_path_config, get_default_bids_visit_label_config
from lib.database import Database
from lib.db.models.session import DbSession
from lib.db.queries.candidate import try_get_candidate_with_psc_id
from lib.db.queries.session import try_get_session_with_cand_id_visit_label
from lib.eeg import Eeg
from lib.env import Env
from lib.import_bids_dataset.args import Args
from lib.import_bids_dataset.check_subjects_sessions import (
    check_bids_session_labels,
    check_or_create_bids_subjects_and_sessions,
)
from lib.import_bids_dataset.copy_files import (
    copy_bids_tsv_participants,
    copy_bids_tsv_scans,
    copy_static_dataset_files,
    get_loris_bids_path,
)
from lib.import_bids_dataset.env import BidsImportEnv
from lib.import_bids_dataset.events import get_root_events_metadata
from lib.import_bids_dataset.meg import import_bids_meg_acquisition
from lib.import_bids_dataset.mri import import_bids_mri_acquisition
from lib.import_bids_dataset.print import print_bids_import_summary
from lib.logging import log, log_error, log_error_exit, log_warning
from lib.util.iter import count


def import_bids_dataset(env: Env, args: Args, legacy_db: Database):
    """
    Read the provided BIDS dataset and import it into LORIS.
    """

    data_dir_path = get_data_dir_path_config(env)

    log(env, "Parsing BIDS dataset...")

    bids = BIDSDataset(args.source_bids_path, args.bids_validation)

    acquisitions_count = count(bids.acquisitions)

    log(env, f"Found {acquisitions_count} acquisitions.")

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

    events_metadata = get_root_events_metadata(env, args, bids, loris_bids_path, project_id)

    # Copy the `participants.tsv` file rows.

    if loris_bids_path is not None and bids.tsv_participants is not None:
        loris_participants_tsv_path = loris_bids_path / 'participants.tsv'
        copy_bids_tsv_participants(bids.tsv_participants, loris_participants_tsv_path)

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
        tsv_scans = bids_session.tsv_scans

        if import_env.loris_bids_path is not None and tsv_scans is not None:
            loris_scans_tsv_path = (
                import_env.loris_bids_path
                / f'sub-{bids_session.subject.label}'
                / f'ses-{bids_session.label}'
                / f'sub-{bids_session.subject.label}_ses-{bids_session.label}_scans.tsv'
            )

            copy_bids_tsv_scans(tsv_scans, loris_scans_tsv_path)
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
    data_type: BidsDataType,
    events_metadata: dict[Any, Any],
    legacy_db: Database,
):
    """
    Read the provided BIDS data type directory and import it into LORIS.
    """

    match data_type:
        case BidsMriDataType() | BidsMegDataType():
            import_bids_data_type_acquisitions(
                env,
                import_env,
                data_type,
                lambda acquisition: import_bids_acquisition(env, import_env, args, session, acquisition),
            )
        case BidsEegDataType():
            import_bids_eeg_data_type_files(env, import_env, args, session, data_type, events_metadata, legacy_db)
        case _:
            log_warning(env, f"Unknown data type '{data_type.name}'. Skipping.")


def import_bids_data_type_acquisitions(
    env: Env,
    import_env: BidsImportEnv,
    data_type: BidsDataType,
    import_acquisition: Callable[[BidsAcquisition], None],
):
    """
    Read the BIDS MRI data type directory and import its files into LORIS.
    Read a BIDS data type directory and import its acquisitions into LORIS.
    """

    log(env, f"Importing data type {data_type.name}")

    if data_type.session.tsv_scans is None:
        log_warning(env, "No 'scans.tsv' file found, 'scans.tsv' data will be ignored.")

    for acquisition in data_type.acquisitions:
        try:
            import_acquisition(acquisition)
        except Exception as exception:
            import_env.failed_files_count += 1
            log_error(
                env,
                (
                    f"Error while importing acquisition '{acquisition.name}'. Error message:\n"
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
    acquisition: BidsAcquisition,
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

    # Get the relevant `scans.tsv` row if there is one.

    if acquisition.session.tsv_scans is not None:
        tsv_scan = acquisition.session.tsv_scans.get_row(acquisition.path)
        if tsv_scan is None:
            log_warning(
                env,
                f"No row for acquisition '{acquisition.name}' found in 'scans.tsv', 'scans.tsv' data will be ignored.",
            )

    else:
        tsv_scan = None

    # Get the path at which to copy the file.

    match acquisition:
        case BidsMriAcquisition():
            import_bids_mri_acquisition(env, import_env, session, acquisition, tsv_scan)
        case BidsMegAcquisition():
            import_bids_meg_acquisition(env, import_env, args, session, acquisition, tsv_scan)
        case _:
            log_warning(env, f"Unknown acquisition type '{acquisition.name}'. Skipping.")

    print(f"Successfully imported acquisition '{acquisition.name}'.")


def import_bids_eeg_data_type_files(
    env: Env,
    import_env: BidsImportEnv,
    args: Args,
    session: DbSession,
    data_type: BidsEegDataType,
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
        env                    = env,
        data_type              = data_type,
        db                     = legacy_db,
        verbose                = env.verbose,
        data_dir               = str(import_env.data_dir_path),
        session                = session,
        loris_bids_eeg_rel_dir = loris_data_type_dir_rel_path,
        loris_bids_root_dir    = str(import_env.loris_bids_path),
        dataset_tag_dict       = events_metadata,
        dataset_type           = args.type,
    )
