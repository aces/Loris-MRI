from pathlib import Path

from loris_bids_reader.json import BidsJsonFile
from loris_utils.crypto import compute_file_blake2b_hash

from lib.db.models.physio_event_file import DbPhysioEventFile
from lib.db.models.project import DbProject
from lib.env import Env
from lib.import_bids_dataset.copy_files import copy_loris_bids_file, get_loris_bids_root_file_path
from lib.import_bids_dataset.env import BidsImportEnv
from lib.physio.events import EventDictFileSource, insert_event_dict_file, parse_and_insert_event_dict
from lib.physio.parameters import insert_physio_file_parameter, insert_physio_project_parameter
from lib.physiological import Physiological


def import_bids_root_event_dict_file(
    env: Env,
    import_env: BidsImportEnv,
    project: DbProject,
    bids_event_dict_file: BidsJsonFile,
) -> tuple[DbPhysioEventFile, dict[str, dict[str, list[list[Physiological.TagGroupMember]]]]]:
    """
    Import a root-level BIDS event dictionary file and its associated HED tags into LORIS.
    """

    loris_event_dict_file_path = get_loris_bids_root_file_path(import_env, bids_event_dict_file.path)

    copy_loris_bids_file(import_env, bids_event_dict_file.path, loris_event_dict_file_path)

    event_dict_file, hed_tags_dict = insert_bids_event_dict_file(
        env,
        EventDictFileSource.from_dataset(project),
        bids_event_dict_file,
        loris_event_dict_file_path,
    )

    env.db.commit()

    return event_dict_file, hed_tags_dict


def insert_bids_event_dict_file(
    env: Env,
    source: EventDictFileSource,
    bids_event_dict_file: BidsJsonFile,
    loris_event_dict_file_path: Path,
) -> tuple[DbPhysioEventFile, dict[str, dict[str, list[list[Physiological.TagGroupMember]]]]]:
    """
    Insert a BIDS event dictionary file and its associated HED tags into the LORIS database.
    """

    event_dict_file = insert_event_dict_file(env, source, loris_event_dict_file_path)

    blake2b_hash = compute_file_blake2b_hash(bids_event_dict_file.path)

    hed_tags_dict = parse_and_insert_event_dict(env, bids_event_dict_file.data, source)

    if source.physio_file is not None:
        insert_physio_file_parameter(env, source.physio_file, 'event_file_json_blake2b_hash', blake2b_hash)
    else:
        insert_physio_project_parameter(env, source.project.id, 'event_file_json_blake2b_hash', blake2b_hash)

    return event_dict_file, hed_tags_dict
