import re
import shutil
from pathlib import Path

from loris_bids_reader.files.dataset_description import BidsDatasetDescriptionJsonFile
from loris_bids_reader.files.participants import BidsParticipantsTsvFile
from loris_bids_reader.files.scans import BidsScansTsvFile

from lib.config import get_data_dir_path_config
from lib.db.models.session import DbSession
from lib.env import Env
from lib.import_bids_dataset.env import BidsImportEnv


def get_loris_bids_dataset_path(env: Env, dataset_description: BidsDatasetDescriptionJsonFile) -> Path:
    """
    Get the LORIS BIDS directory path for the BIDS dataset to import, and create that directory if
    it does not exist yet.
    """

    # Sanitize the dataset metadata to have a usable name for the directory.
    dataset_name    = re.sub(r'[^0-9a-zA-Z]+',   '_', dataset_description.data['Name'])
    dataset_version = re.sub(r'[^0-9a-zA-Z\.]+', '_', dataset_description.data['BIDSVersion'])

    data_dir_path = get_data_dir_path_config(env)
    loris_bids_path = data_dir_path / 'bids_imports' / f'{dataset_name}_BIDSVersion_{dataset_version}'

    if not loris_bids_path.exists():
        loris_bids_path.mkdir()

    return loris_bids_path


def get_loris_bids_root_file_path(import_env: BidsImportEnv, file_path: Path) -> Path:
    """
    Get the path of a BIDS file relative to the LORIS data directory, maintaining the same relative
    path in the LORIS BIDS dataset as within the source BIDS dataset.
    """

    # In the import is run in no-copy mode, return the original file path.
    if import_env.loris_bids_path is None:
        return file_path.relative_to(import_env.data_dir_path)

    return import_env.loris_bids_path / file_path.relative_to(import_env.source_bids_path)


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

    # In the import is run in no-copy mode, return the original file path.
    if import_env.loris_bids_path is None:
        return file_path.relative_to(import_env.data_dir_path)

    # If the file is a derivative, the path is unpredictable, so return a copy of that path in the
    # LORIS BIDS dataset.
    if derivative:
        return import_env.loris_bids_path / file_path.relative_to(import_env.source_bids_path)

    # Otherwise, normalize the subject and session directrory names using the LORIS session
    # information.
    loris_file_name = get_loris_bids_file_name(file_path.name, session)

    return (
        import_env.loris_bids_path
        / f'sub-{session.candidate.psc_id}'
        / f'ses-{session.visit_label}'
        / data_type
        / loris_file_name
    )


def get_loris_bids_file_name(file_name: str, session: DbSession) -> str:
    """
    Get the name of a BIDS file in LORIS, replacing or adding the BIDS subject and session labels
    with the LORIS PSCID and visit label.
    """

    # Remove the subject and session entities if they are present.
    file_name = re.sub(r'sub-[a-zA-Z0-9]+_?', '', file_name)
    file_name = re.sub(r'ses-[a-zA-Z0-9]+_?', '', file_name)

    # Add the LORIS subject and session information back in the correct order.
    return f'sub-{session.candidate.psc_id}_ses-{session.visit_label}_{file_name}'


def get_loris_scans_path(import_env: BidsImportEnv, scans_file: BidsScansTsvFile, session: DbSession) -> Path:
    """
    Get the path of a `scans.tsv` file in LORIS, relative to the LORIS data directory.
    """

    # In the import is run in no-copy mode, return the original file path.
    if import_env.loris_bids_path is None:
        return scans_file.path.relative_to(import_env.data_dir_path)

    loris_file_name = get_loris_bids_file_name(scans_file.path.name, session)
    return (
        import_env.loris_bids_path
        / f'sub-{session.candidate.psc_id}'
        / f'ses-{session.visit_label}'
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


def copy_bids_static_files(import_env: BidsImportEnv):
    """
    Copy the static files of the source BIDS dataset to the LORIS BIDS dataset.
    """

    # Do not copy files in no-copy mode.
    if import_env.loris_bids_path is None:
        return

    for file_name in ['README', 'dataset_description.json']:
        source_file_path = import_env.source_bids_path / file_name
        if not source_file_path.is_file():
            continue

        loris_file_path = import_env.loris_bids_path / file_name

        # Do not copy the file if it is already present during an incremental import.
        if (import_env.data_dir_path / loris_file_path).is_file():
            continue

        copy_loris_bids_file(import_env, source_file_path, loris_file_path)


def copy_bids_participants_file(
    import_env: BidsImportEnv,
    participants_file: BidsParticipantsTsvFile,
    loris_participants_path: Path,
):
    """
    Copy some `participants.tsv` rows into the LORIS `participants.tsv` file, creating it if
    necessary.
    """

    # Do not copy the file in no-copy mode.
    if import_env.loris_bids_path is None:
        return

    participants_path = import_env.data_dir_path / loris_participants_path
    if participants_path.exists():
        participants_file.merge(BidsParticipantsTsvFile(participants_path))

    participants_path.parent.mkdir(parents=True, exist_ok=True)
    participants_file.write(participants_path)


def copy_bids_scans_file(import_env: BidsImportEnv, scans_file: BidsScansTsvFile, loris_scans_path: Path):
    """
    Copy some `scans.tsv` rows into a LORIS `scans.tsv` file, creating it if necessary.
    """

    # Do not copy the file in no-copy mode.
    if import_env.loris_bids_path is None:
        return

    scans_path = import_env.data_dir_path / loris_scans_path
    if scans_path.exists():
        scans_file.merge(BidsScansTsvFile(scans_path))

    scans_path.parent.mkdir(parents=True, exist_ok=True)
    scans_file.write(scans_path)
