from typing import Any

from loris_bids_reader.meg.reader import BidsMegDataTypeReader
from loris_bids_reader.mri.reader import BidsMriDataTypeReader
from loris_bids_reader.reader import BidsDatasetReader, BidsDataTypeReader, BidsSessionReader

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
    copy_bids_participants_file,
    copy_bids_scans_file,
    copy_bids_static_files,
    get_loris_bids_dataset_path,
    get_loris_bids_root_file_path,
    get_loris_scans_path,
)
from lib.import_bids_dataset.env import BidsImportEnv
from lib.import_bids_dataset.events import import_bids_root_event_dict_file
from lib.import_bids_dataset.meg import import_bids_meg_data_type
from lib.import_bids_dataset.mri import import_bids_mri_data_type
from lib.import_bids_dataset.print import print_bids_import_summary, print_bids_info
from lib.logging import log, log_error_exit, log_warning


def import_bids_dataset(env: Env, args: Args, legacy_db: Database):
    """
    Read the provided BIDS dataset and import it into LORIS.
    """

    data_dir_path = get_data_dir_path_config(env)

    log(env, "Parsing BIDS dataset...")

    bids = BidsDatasetReader(args.source_bids_path, args.type == 'derivative', args.bids_validation)

    print_bids_info(env, bids)

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

    # Assumption all same project (for project-wide tags)
    single_project = sessions[0].project

    env.db.commit()

    # Get the LORIS BIDS import directory path and create the directory if needed.

    if args.copy:
        try:
            dataset_description = bids.dataset_description_file
        except Exception as error:
            log_error_exit(env, str(error))

        if dataset_description is None:
            log_error_exit(
                env,
                "No file 'dataset_description.json' found in the input BIDS dataset.",
            )

        loris_bids_path = get_loris_bids_dataset_path(env, dataset_description)
    else:
        loris_bids_path = None

    import_env = BidsImportEnv(
        data_dir_path     = data_dir_path,
        loris_bids_path   = loris_bids_path.relative_to(data_dir_path) if loris_bids_path is not None else None,
        source_bids_path  = args.source_bids_path,
    )

    # Copy the static BIDS files.

    copy_bids_static_files(import_env)

    # Get the BIDS event dictionary.

    if bids.event_dict_file is None:
        dataset_tag_dict: dict[Any, Any] = {}
        log_warning(env, "No events dictionary files (events.json) in root directory.")
    else:
        _, dataset_tag_dict = import_bids_root_event_dict_file(
            env,
            import_env,
            single_project,
            bids.event_dict_file,
        )

    # Copy the `participants.tsv` file rows.

    if bids.participants_file is not None:
        loris_participants_path = get_loris_bids_root_file_path(import_env, bids.participants_file.path)
        copy_bids_participants_file(import_env, bids.participants_file, loris_participants_path)

    # Process each session directory.

    for bids_session in bids.sessions:
        import_bids_session(env, import_env, args, bids_session, dataset_tag_dict, legacy_db)

    # Print import summary.

    print_bids_import_summary(env, import_env)


def import_bids_session(
    env: Env,
    import_env: BidsImportEnv,
    args: Args,
    bids_session: BidsSessionReader,
    dataset_tag_dict: dict[Any, Any],
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
        if bids_session.scans_file is not None:
            loris_scans_path = get_loris_scans_path(import_env, bids_session.scans_file, session)
            copy_bids_scans_file(import_env, bids_session.scans_file, loris_scans_path)
    except Exception as exception:
        log_warning(
            env,
            f"Error while reading the session scans.tsv file, scans.tsv data will be ignored. Full error:\n{exception}"
        )

    # Process each data type directory.

    for data_type in bids_session.data_types:
        import_bids_data_type(env, import_env, args, session, data_type, dataset_tag_dict, legacy_db)


def import_bids_data_type(
    env: Env,
    import_env: BidsImportEnv,
    args: Args,
    session: DbSession,
    data_type: BidsDataTypeReader,
    dataset_tag_dict: dict[Any, Any],
    legacy_db: Database,
):
    """
    Read the provided BIDS data type directory and import it into LORIS.
    """

    log(env, f"Importing data type {data_type.name}")

    if data_type.session.scans_file is None:
        log_warning(env, "No 'scans.tsv' file found, 'scans.tsv' data will be ignored.")

    match data_type:
        case BidsMriDataTypeReader():
            import_bids_mri_data_type(env, import_env, session, data_type)
        case BidsMegDataTypeReader():
            import_bids_meg_data_type(env, import_env, args, session, data_type)
        case BidsDataTypeReader():
            import_bids_eeg_data_type_files(env, import_env, args, session, data_type, dataset_tag_dict, legacy_db)


def import_bids_eeg_data_type_files(
    env: Env,
    import_env: BidsImportEnv,
    args: Args,
    session: DbSession,
    data_type: BidsDataTypeReader,
    dataset_tag_dict: dict[Any, Any],
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
        dataset_tag_dict       = dataset_tag_dict,
        dataset_type           = args.type,
    )
