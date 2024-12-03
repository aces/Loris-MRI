import re
import shutil
from pathlib import Path

from loris_bids_reader.dataset import BidsAcquisition, BIDSDataset
from loris_bids_reader.files.participants import BidsParticipantsTsvFile
from loris_bids_reader.files.scans import BidsScansTsvFile

from lib.db.models.session import DbSession
from lib.env import Env
from lib.import_bids_dataset.env import BidsImportEnv
from lib.logging import log_error_exit


def get_loris_bids_path(env: Env, bids: BIDSDataset, data_dir_path: Path) -> Path:
    """
    Get the LORIS BIDS directory path for the BIDS dataset to import, and create that directory if
    it does not exist yet.
    """

    try:
        dataset_description = bids.get_dataset_description()
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


def get_loris_file_path(
    import_env: BidsImportEnv,
    session: DbSession,
    acquisition: BidsAcquisition,
    file_path: Path,
) -> Path:
    if import_env.loris_bids_path is None:
        return file_path

    loris_file_path = (
        import_env.loris_bids_path
        / f'sub-{session.candidate.psc_id}'
        / f'ses-{session.visit_label}'
        / acquisition.data_type.name
        / file_path.name
    )

    return loris_file_path.relative_to(import_env.data_dir_path)


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


def copy_bids_file(loris_bids_path: Path, session: DbSession, acquisition: BidsAcquisition, file_path: Path):
    """
    Copy a BIDS file to a directory.
    """

    loris_file_path = (
        loris_bids_path
        / f'sub-{session.candidate.psc_id}'
        / f'ses-{session.visit_label}'
        / acquisition.data_type.name
        / file_path.name
    )

    if loris_file_path.exists():
        raise Exception(f"File '{loris_file_path}' already exists in LORIS.")

    loris_file_path.parent.mkdir(parents=True, exist_ok=True)
    if file_path.is_file():
        shutil.copyfile(file_path, loris_file_path)
    elif file_path.is_dir():
        shutil.copytree(file_path, loris_file_path)


def archive_bids_directory(loris_bids_path: Path, session: DbSession, acquisition: BidsAcquisition, dir_path: Path):
    loris_archive_path = (
        loris_bids_path
        / f'sub-{session.candidate.psc_id}'
        / f'ses-{session.visit_label}'
        / acquisition.data_type.name
        / f'{dir_path.name}.tar.gz'
    )

    if loris_archive_path.exists():
        raise Exception(f"File '{loris_archive_path}' already exists in LORIS.")

    if loris_archive_path.name.endswith('.tar.gz'):
        loris_archive_path = loris_archive_path.with_name(loris_archive_path.name[:-7])

    shutil.make_archive(str(loris_archive_path), 'gztar', dir_path)
