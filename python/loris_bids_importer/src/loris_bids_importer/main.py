from typing import Any

from lib.db.models.session import DbSession
from lib.env import Env
from lib.logging import log, log_error, log_warning
from loris_bids_utils.mri.reader import BidsMriDataTypeReader
from loris_bids_utils.reader import BidsDatasetReader, BidsDataTypeReader, BidsSessionReader

from loris_bids_importer.config import load_bids_config
from loris_bids_importer.copy_files import (
    copy_bids_participants_file,
    copy_bids_sessions_file,
    copy_bids_static_files,
)
from loris_bids_importer.dataset import make_bids_importer
from loris_bids_importer.eeg.main import Eeg
from loris_bids_importer.events import import_bids_root_event_dict_file
from loris_bids_importer.importer import BidsImporter, BidsImporterArgs
from loris_bids_importer.mri.main import import_bids_mri_data_type
from loris_bids_importer.print import print_bids_import_summary, print_bids_info
from loris_bids_importer.resolution.dataset import resolve_bids_mappings


def import_bids_dataset(env: Env, args: BidsImporterArgs):
    """
    Read the provided BIDS dataset and import it into LORIS.
    """

    log(env, "Parsing BIDS dataset...")

    bids = BidsDatasetReader(args.source_bids_path, args.type == 'derivative', args.bids_validation)

    print_bids_info(env, bids)

    # Configure, get, or create the LORIS candidates and sessions of this BIDS dataset.

    config = load_bids_config(args.bids_config_path)
    mappings = resolve_bids_mappings(env, bids, config)
    sessions = list(mappings.sessions.values())

    log(
        env,
        f"Selected {len(mappings.candidates)} subjects and {len(sessions)} sessions; skipped"
        f" {len(bids.subjects) - len(mappings.candidates)} subjects and"
        f" {len(bids.sessions) - len(sessions)} sessions.",
    )

    if sessions == []:
        log(env, "No sessions selected for import. Nothing to import.")
        return

    # Assumption all same project (for project-wide tags)
    single_project = sessions[0].project

    env.db.commit()

    importer = make_bids_importer(env, args, bids)

    # Copy the static BIDS files.

    copy_bids_static_files(env, importer)

    # Get the BIDS event dictionary.

    if bids.event_dict_file is None:
        dataset_tag_dict: dict[Any, Any] = {}
        log_warning(env, "No events dictionary files (events.json) in root directory.")
    else:
        _, dataset_tag_dict = import_bids_root_event_dict_file(
            env,
            importer,
            single_project,
            bids.event_dict_file,
        )

    # Copy the `participants.tsv` file rows.

    if bids.participants_file is not None:
        copy_bids_participants_file(
            env,
            importer,
            bids.participants_file,
            mappings.candidates,
        )

    # Copy the `sessions.tsv` files, translating their subject and session identifiers.

    for bids_subject in bids.subjects:
        if bids_subject.label not in mappings.candidates or bids_subject.sessions_file is None:
            continue

        candidate = mappings.candidates[bids_subject.label]
        subject_sessions = {
            bids_session.label: mappings.sessions[bids_session.subject_session_label]
            for bids_session in bids_subject.sessions
            if bids_session.label is not None and bids_session.subject_session_label in mappings.sessions
        }

        copy_bids_sessions_file(
            env,
            importer,
            bids_subject.sessions_file,
            candidate,
            subject_sessions,
        )

    # Process each session directory.

    for bids_session in bids.sessions:
        session = mappings.sessions.get(bids_session.subject_session_label)
        if session is None:
            continue

        import_bids_session(env, importer, bids_session, session, dataset_tag_dict)

    # Print import summary.

    print_bids_import_summary(env, importer)


def import_bids_session(
    env: Env,
    importer: BidsImporter,
    bids_session: BidsSessionReader,
    session: DbSession,
    dataset_tag_dict: dict[Any, Any],
):
    """
    Read the provided BIDS session directory and import it into LORIS.
    """

    log(env, f"Importing files for subject '{bids_session.subject.label}' and session '{bids_session.label}'.")

    # Process each data type directory.

    for data_type in bids_session.data_types:
        import_bids_data_type(env, importer, session, data_type, dataset_tag_dict)


def import_bids_data_type(
    env: Env,
    importer: BidsImporter,
    session: DbSession,
    data_type: BidsDataTypeReader,
    dataset_tag_dict: dict[Any, Any],
):
    """
    Read the provided BIDS data type directory and import it into LORIS.
    """

    log(env, f"Importing data type {data_type.name}")

    if data_type.session.scans_file is None:
        log_warning(env, "No 'scans.tsv' file found, 'scans.tsv' data will be ignored.")

    match data_type:
        case BidsMriDataTypeReader():
            import_bids_mri_data_type(env, importer, session, data_type)
        case BidsDataTypeReader():
            import_bids_eeg_data_type_files(env, importer, session, data_type, dataset_tag_dict)


def import_bids_eeg_data_type_files(
    env: Env,
    importer: BidsImporter,
    session: DbSession,
    data_type: BidsDataTypeReader,
    dataset_tag_dict: dict[Any, Any],
):
    """
    Read the provided BIDS EEG data type directory and import it into LORIS.
    """

    try:
        Eeg(
            env              = env,
            importer         = importer,
            bids_layout      = data_type.session.subject.dataset.layout,
            bids_info        = data_type.info,
            session          = session,
            dataset_tag_dict = dataset_tag_dict,
        )
    except Exception as exception:
        log_error(
            env,
            (
                f"Error while importing EEG session. Error message:\n"
                f"{exception}\n"
                "Skipping."
            )
        )
        importer.failed_acquisitions_count += 1
