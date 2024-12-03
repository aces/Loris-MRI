from pathlib import Path

from lib.db.models.physio_file import DbPhysioFile
from lib.db.queries.bids import get_physio_files_with_bids_dataset_id
from lib.db.queries.bids_file import try_get_bids_file_with_dataset_id_path
from lib.env import Env
from lib.logging import log, log_error
from loris_bids_importer.copy_files import copy_loris_bids_file, get_loris_bids_root_file_path
from loris_bids_importer.dataset import get_or_create_loris_bids_file
from loris_bids_importer.importer import BidsImporter
from loris_bids_utils.path import parse_bids_entities
from loris_bids_utils.reader import BidsDatasetReader
from loris_utils.fs import iter_all_dir_files

from loris_meegqc_module.database.models.meegqc_file import DbMeegqcFile
from loris_meegqc_module.database.queries.meegqc_file import try_get_meegqc_file_with_bids_info_id

MEEGQC_ROOT_CATEGORY = 'root'


def import_meegqc_derivatives(env: Env, importer: BidsImporter, bids_dataset: BidsDatasetReader):
    print("Running MEEGQC importer")

    meegqc_path = bids_dataset.path / 'derivatives' / 'MEEGqc'
    if not meegqc_path.exists():
        log(env, "No MEEGqc derivatives found in the BIDS dataset. Skipping.")
        return

    import_meegqc_files(env, importer, meegqc_path)


def import_meegqc_files(env: Env, importer: BidsImporter, meegqc_path: Path):
    print("Importing MEEGqc files")

    for relative_file_path in iter_all_dir_files(meegqc_path):
        file_path = meegqc_path / relative_file_path
        category = relative_file_path.parts[0] if len(relative_file_path.parts) > 1 else MEEGQC_ROOT_CATEGORY
        try:
            import_meegqc_file(env, importer, file_path, category)
        except Exception as exception:
            log_error(env, f"Error while importing MEEGqc file '{file_path}'. Error message:\n{exception}")


def import_meegqc_file(env: Env, importer: BidsImporter, meegqc_file_path: Path, category: str):
    log(env, f"Importing MEEGqc {category} file '{meegqc_file_path}'.")

    try:
        acquisition_files = find_acquisition_files(env, importer, meegqc_file_path, category)

        loris_file_path = get_loris_bids_root_file_path(importer, meegqc_file_path)
        bids_file_path = loris_file_path.relative_to(importer.loris_bids_dataset.path)

        current_bids_file = try_get_bids_file_with_dataset_id_path(
            env.db,
            importer.loris_bids_dataset.id,
            bids_file_path,
        )

        if current_bids_file is not None:
            current_meegqc_file = try_get_meegqc_file_with_bids_info_id(env.db, current_bids_file.id)
            if current_meegqc_file is not None:
                log(env, f"A MEEGqc file with path {loris_file_path} already exists in the database. Skipping.")
                return

        copy_loris_bids_file(importer, meegqc_file_path, loris_file_path)

        bids_file = get_or_create_loris_bids_file(env, importer, meegqc_file_path, loris_file_path)

        env.db.add(DbMeegqcFile(
            bids_info_id       = bids_file.id,
            category          = category,
            acquisition_files = acquisition_files,
        ))

        env.db.commit()
    except Exception:
        env.db.rollback()
        raise


def find_acquisition_files(
    env: Env,
    importer: BidsImporter,
    meegqc_file_path: Path,
    category: str,
) -> list[DbPhysioFile]:
    acquisition_files = get_physio_files_with_bids_dataset_id(env.db, importer.loris_bids_dataset.id)

    if category != MEEGQC_ROOT_CATEGORY:
        meegqc_entities = parse_bids_entities(meegqc_file_path.name)
        meegqc_entities.pop('desc', None)
    else:
        meegqc_entities = {}

    matching_acquisition_files: list[DbPhysioFile] = []
    for acquisition_file in acquisition_files:
        if acquisition_file.bids_info is None or acquisition_file.bids_info.source_path is None:
            continue

        acquisition_entities = parse_bids_entities(acquisition_file.bids_info.source_path.name)
        if acquisition_entities.items() >= meegqc_entities.items():
            matching_acquisition_files.append(acquisition_file)

    return matching_acquisition_files
