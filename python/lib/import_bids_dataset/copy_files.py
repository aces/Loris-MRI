import re
import shutil
from pathlib import Path

from loris_bids_reader.files.participants import BidsParticipantsTsvFile
from loris_bids_reader.files.scans import BidsScansTsvFile
from loris_bids_reader.reader import BidsDatasetReader

from lib.db.models.session import DbSession
from lib.env import Env
from lib.import_bids_dataset.env import BidsImportEnv
from lib.logging import log_error_exit


def get_loris_bids_dataset_path(env: Env, bids: BidsDatasetReader, data_dir_path: Path) -> Path:
    """
    Get the LORIS BIDS directory path for the BIDS dataset to import, and create that directory if
    it does not exist yet.
    """

    try:
        dataset_description = bids.dataset_description_file
    except Exception as error:
        log_error_exit(env, str(error))

    if dataset_description is None:
        log_error_exit(
            env,
            "No file 'dataset_description.json' found in the input BIDS dataset.",
        )

    # Sanitize the dataset metadata to have a usable name for the directory.
    dataset_name    = re.sub(r'[^0-9a-zA-Z]+',   '_', dataset_description.data['Name'])
    dataset_version = re.sub(r'[^0-9a-zA-Z\.]+', '_', dataset_description.data['BIDSVersion'])

    loris_bids_path = data_dir_path / 'bids_imports' / f'{dataset_name}_BIDSVersion_{dataset_version}'

    if not loris_bids_path.exists():
        loris_bids_path.mkdir()

    return loris_bids_path


def get_loris_bids_file_path(
    import_env: BidsImportEnv,
    session: DbSession,
    data_type: str,
    file_path: Path,
    derivative: bool = False,
) -> Path:
    """
    Get the path of a BIDS file in LORIS, relative to the LORIS data directory.
    """

    # In the import is run in no-copy mode, simply return the original file path.
    if import_env.loris_bids_path is None:
        return file_path.relative_to(import_env.data_dir_path)

    # If the file is a derivative, the path is unpredictable, so return a copy of that path in the
    # LORIS BIDS dataset.
    if derivative:
        return import_env.loris_bids_path / file_path.relative_to(import_env.source_bids_path)

    # Otherwise, normalize the subject and session directrory names using the LORIS session
    # information.
    loris_file_name = file_path.name
    loris_file_name = re.sub(r'sub-[a-zA-Z0-9]+', f'sub-{session.candidate.psc_id}', loris_file_name)
    loris_file_name = re.sub(r'ses-[a-zA-Z0-9]+', f'ses-{session.visit_label}',      loris_file_name)

    return (
        import_env.loris_bids_path
        / f'sub-{session.candidate.psc_id}'
        / f'ses-{session.visit_label}'
        / data_type
        / loris_file_name
    )


def copy_loris_bids_file(import_env: BidsImportEnv, file_path: Path, loris_file_path: Path):
    """
    Copy a BIDS file to the LORIS data directory, unless the no-copy mode is enabled.
    """

    # Do not copy the file in no-copy mode.
    if import_env.loris_bids_path is None:
        return

    full_loris_file_path = import_env.data_dir_path / loris_file_path

    if full_loris_file_path.exists():
        raise Exception(f"File '{loris_file_path}' already exists in LORIS.")

    full_loris_file_path.parent.mkdir(parents=True, exist_ok=True)
    if file_path.is_file():
        shutil.copyfile(file_path, full_loris_file_path)
    elif file_path.is_dir():
        shutil.copytree(file_path, full_loris_file_path)


def copy_static_dataset_files(source_bids_path: Path, loris_bids_path: Path):
    """
    Copy the static files of the source BIDS dataset to the LORIS BIDS dataset.
    """

    for file_name in ['README', 'dataset_description.json']:
        source_file_path = source_bids_path / file_name
        if not source_file_path.is_file():
            continue

        loris_file_path = loris_bids_path / file_name
        shutil.copyfile(source_file_path, loris_file_path)


def copy_bids_tsv_participants(tsv_participants: BidsParticipantsTsvFile, loris_participants_tsv_path: Path):
    """
    Copy some participants.tsv rows into the LORIS participants.tsv file, creating it if necessary.
    """

    if loris_participants_tsv_path.exists():
        tsv_participants.merge(BidsParticipantsTsvFile(loris_participants_tsv_path))

    tsv_participants.write(loris_participants_tsv_path, ['participant_id'])


def copy_bids_tsv_scans(tsv_scans: BidsScansTsvFile, loris_scans_tsv_path: Path):
    """
    Copy some scans.tsv rows into a LORIS scans.tsv file, creating it if necessary.
    """

    if loris_scans_tsv_path.exists():
        tsv_scans.merge(BidsScansTsvFile(loris_scans_tsv_path))

    tsv_scans.write(loris_scans_tsv_path, ['filename', 'acq_time', 'age_at_scan'])
