import re
from pathlib import Path

from lib.db.models.physio_file import DbPhysioFile
from lib.db.queries.physio_file import try_get_physio_file_with_path
from lib.env import Env
from lib.logging import log, log_error, log_warning
from loris_bids_importer.copy_files import copy_loris_bids_file, get_loris_bids_root_file_path
from loris_bids_importer.importer import BidsImporter
from loris_bids_utils.reader import BidsDatasetReader
from loris_utils.crypto import compute_file_blake2b_hash
from loris_utils.fs import iter_all_dir_files
from loris_utils.iter import find

from loris_meegqc_module.database.models.meegqc_file import DbMeegqcFile
from loris_meegqc_module.database.queries.meegqc_file import try_get_meegqc_file_with_path


def import_meegqc_derivatives(env: Env, importer: BidsImporter, bids_dataset: BidsDatasetReader):
    print("Running MEEGQC importer")

    meegqc_path = bids_dataset.path / 'derivatives' / 'Meg_QC'
    if not meegqc_path.exists():
        log(env, "No MEEGqc derivatives found in the BIDS dataset. Skipping.")
        return

    for kind in ['calculation', 'summary_reports', 'reports']:
        kind_path = meegqc_path / kind
        if not kind_path.exists():
            log_warning(env, f"No MEEGqc files found for kind '{kind}'.")
            continue

        import_meegqc_files(env, importer, kind_path, kind)


def import_meegqc_files(env: Env, importer: BidsImporter, kind_path: Path, kind: str):
    print(f"Importing MEEGqc files for kind '{kind}'")

    for file_path in iter_all_dir_files(kind_path):
        try:
            import_meegqc_file(env, importer, file_path, kind)
        except Exception as exception:
            log_error(env, f"Error while importing MEEGqc file '{file_path}'. Error message:\n{exception}")


def import_meegqc_file(env: Env, importer: BidsImporter, meegqc_file_path: Path, kind: str):
    log(env, f"Importing MEEGqc {kind} file '{meegqc_file_path}'.")

    full_file_path = importer.args.source_bids_path / meegqc_file_path

    acquisition_file = find_acquisition_file(env, importer, full_file_path)

    blake2b_hash = compute_file_blake2b_hash(full_file_path)

    loris_file_path = get_loris_bids_root_file_path(importer, full_file_path)

    current_meegqc_file = try_get_meegqc_file_with_path(env.db, loris_file_path)
    if current_meegqc_file is not None:
        log(env, f"A MEEGqc file with path {loris_file_path} already exists in the database. Skipping.")
        return

    copy_loris_bids_file(importer, meegqc_file_path, loris_file_path)

    env.db.add(DbMeegqcFile(
        acquisition_file_id=acquisition_file.id,
        path=loris_file_path,
        kind=kind,
        blake2b_hash=blake2b_hash,
    ))

    env.db.commit()


def find_acquisition_file(env: Env, importer: BidsImporter, meegqc_file_path: Path) -> DbPhysioFile:
    # TODO: Use a general BIDS file name abstraction.
    meegqc_file_pattern = re.sub(r'_run-(\d)', r'_run-0+\1', meegqc_file_path.stem)
    meegqc_file_pattern = re.sub(r'_desc-.+_meg', r'(_.*)?_meg', meegqc_file_pattern)
    entry = find(importer.files_dict.items(), lambda entry: re.match(meegqc_file_pattern, entry[0].stem) is not None)
    if entry is None:
        raise Exception(f"TODO 1 cannot match {meegqc_file_path.stem} ({meegqc_file_pattern})")

    file_path = (
        importer.loris_bids_path / entry[1]
        if importer.loris_bids_path is not None
        else (importer.args.source_bids_path / entry[1]).relative_to(importer.data_dir_path)
    )

    file = try_get_physio_file_with_path(env.db, file_path)
    if file is None:
        raise Exception(f"TODO 2 {entry}")

    return file
