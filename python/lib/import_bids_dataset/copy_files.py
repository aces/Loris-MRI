import os
import re
import shutil
from pathlib import Path

from loris_bids_reader.files.scans import BidsScansTsvFile

import lib.utilities
from lib.db.models.session import DbSession
from lib.import_bids_dataset.env import BidsImportEnv


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


def copy_scans_tsv_file_to_loris_bids_dir(
    scans_file: BidsScansTsvFile,
    bids_sub_id: str,
    loris_bids_root_dir: str,
    data_dir: str,
) -> str:
    """
    Copy the scans.tsv file to the LORIS BIDS directory for the subject.
    """

    original_file_path = scans_file.path
    final_file_path = os.path.join(loris_bids_root_dir, f'sub-{bids_sub_id}', scans_file.path.name)

    # copy the scans.tsv file to the new directory
    if os.path.exists(final_file_path):
        lib.utilities.append_to_tsv_file(original_file_path, final_file_path, 'filename', False)  # type: ignore
    else:
        lib.utilities.copy_file(original_file_path, final_file_path, False)  # type: ignore

    # determine the relative path and return it
    return os.path.relpath(final_file_path, data_dir)
