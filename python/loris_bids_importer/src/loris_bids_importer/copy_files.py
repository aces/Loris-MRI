import re
import shutil
from pathlib import Path

from lib.db.models.session import DbSession
from lib.env import Env
from loris_bids_utils.files.participants import BidsParticipantsTsvFile
from loris_bids_utils.files.scans import BidsScansTsvFile, BidsScanTsvRow
from loris_bids_utils.path import build_bids_modality_path, build_bids_session_path

from loris_bids_importer.dataset import get_or_create_loris_bids_file
from loris_bids_importer.importer import BidsImporter


def get_loris_bids_root_file_path(importer: BidsImporter, file_path: Path) -> Path:
    """
    Get the path of a BIDS file relative to the LORIS data directory, maintaining the same relative
    path in the LORIS BIDS dataset as within the source BIDS dataset.
    """

    # In the import is run in no-copy mode, return the original file path.
    if not importer.args.copy:
        return file_path.relative_to(importer.data_dir_path)

    return importer.loris_bids_dataset.path / file_path.relative_to(importer.args.source_bids_path)


def get_loris_bids_file_path(
    importer: BidsImporter,
    session: DbSession,
    data_type: str,
    file_path: Path,
    derivative: bool = False,
) -> Path:
    """
    Get the path of a BIDS file in LORIS, relative to the LORIS data directory.
    """

    # In the import is run in no-copy mode, return the original file path.
    if not importer.args.copy:
        return file_path.relative_to(importer.data_dir_path)

    # If the file is a derivative, the path is unpredictable, so return a copy of that path in the
    # LORIS BIDS dataset.
    if derivative:
        return importer.loris_bids_dataset.path / file_path.relative_to(importer.args.source_bids_path)

    # Otherwise, normalize the subject and session directory names using the LORIS session
    # information.
    loris_file_name = get_loris_bids_file_name(file_path.name, session)

    return importer.loris_bids_dataset.path / build_bids_modality_path(
        session.candidate.psc_id,
        session.visit_label,
        data_type,
        loris_file_name,
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


def get_loris_scans_path(importer: BidsImporter, scans_file: BidsScansTsvFile, session: DbSession) -> Path:
    """
    Get the path of a `scans.tsv` file in LORIS, relative to the LORIS data directory.
    """

    # In the import is run in no-copy mode, return the original file path.
    if not importer.args.copy:
        return scans_file.path.relative_to(importer.data_dir_path)

    loris_file_name = get_loris_bids_file_name(scans_file.path.name, session)

    return importer.loris_bids_dataset.path / build_bids_session_path(
        session.candidate.psc_id,
        session.visit_label,
        loris_file_name,
    )


def copy_loris_bids_file(importer: BidsImporter, file_path: Path, loris_file_path: Path):
    """
    Copy a BIDS file to the LORIS data directory, unless the no-copy mode is enabled.
    """

    # Do not copy the file in no-copy mode.
    if not importer.args.copy:
        return

    full_loris_file_path = importer.data_dir_path / loris_file_path

    if full_loris_file_path.exists():
        raise Exception(f"File '{loris_file_path}' already exists in the LORIS data directory.")

    full_loris_file_path.parent.mkdir(parents=True, exist_ok=True)
    if file_path.is_file():
        shutil.copyfile(file_path, full_loris_file_path)
    elif file_path.is_dir():
        shutil.copytree(file_path, full_loris_file_path)


def copy_bids_static_files(env: Env, importer: BidsImporter):
    """
    Copy the static files of the source BIDS dataset to the LORIS BIDS dataset.
    """

    for file_name in ['README', 'dataset_description.json']:
        source_file_path = importer.args.source_bids_path / file_name
        if not source_file_path.is_file():
            continue

        loris_file_path = importer.loris_bids_dataset.path / file_name

        # Do not copy the file if it is already present during an incremental import.
        if not (importer.data_dir_path / loris_file_path).is_file():
            copy_loris_bids_file(importer, source_file_path, loris_file_path)

        get_or_create_loris_bids_file(env, importer, source_file_path, loris_file_path)


def copy_bids_participants_file(
    env: Env,
    importer: BidsImporter,
    participants_file: BidsParticipantsTsvFile,
    loris_participants_path: Path,
):
    """
    Copy some `participants.tsv` rows into the LORIS `participants.tsv` file, creating it if
    necessary.
    """

    if importer.args.copy:
        participants_path = importer.data_dir_path / loris_participants_path
        if participants_path.exists():
            participants_file.merge(BidsParticipantsTsvFile(participants_path))

        participants_path.parent.mkdir(parents=True, exist_ok=True)
        participants_file.write(participants_path)

    get_or_create_loris_bids_file(env, importer, participants_file.path, loris_participants_path)


def add_bids_scan_row(
    env: Env,
    importer: BidsImporter,
    scans_file: BidsScansTsvFile,
    scan_row: BidsScanTsvRow,
    loris_scans_path: Path,
):
    """
    Add a BIDS `scans.tsv` row into a LORIS `scans.tsv` file, creating it if necessary.
    """

    if importer.args.copy:
        scans_path = importer.data_dir_path / loris_scans_path

        # Create the LORIS scans.tsv file if it does not exist yet.
        scans_path.touch(exist_ok=True)

        loris_scans_file = BidsScansTsvFile(scans_path)
        loris_scans_file.set_row(scan_row)
        loris_scans_file.write()

    get_or_create_loris_bids_file(env, importer, scans_file.path, loris_scans_path)
