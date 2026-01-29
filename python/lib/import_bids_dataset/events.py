import shutil
from pathlib import Path
from typing import Any

from loris_bids_reader.dataset import BIDSDataset
from loris_bids_reader.json import BidsJsonFile

from lib.db.models.physio_event_file import DbPhysioEventFile
from lib.env import Env
from lib.import_bids_dataset.args import Args
from lib.logging import log_warning
from lib.physio.events import DatasetSource, EventFileSource
from lib.physio.file_parameters import insert_physio_file_parameter
from lib.physio.hed import TagGroupMember, build_hed_tag_groups, insert_hed_tag_group
from lib.util.crypto import compute_file_blake2b_hash


def get_root_events_metadata(
    env: Env,
    args: Args,
    bids: BIDSDataset,
    loris_bids_path: Path | None,
    project_id: int,
) -> dict[str, dict[str, list[TagGroupMember]]]:
    """
    Get the root level 'events.json' data, assuming a singe project for the BIDS dataset.
    """

    events_metadata_file = bids.json_events

    if events_metadata_file is None:
        log_warning(env, "No event metadata files (events.json) in the BIDS root directory.")
        return {}

    # Copy the event file to the LORIS BIDS import directory.

    if loris_bids_path is not None:
        events_metadata_rel_path = events_metadata_file.path.relative_to(loris_bids_path)
        events_metadata_path = loris_bids_path / events_metadata_rel_path
        shutil.copyfile(events_metadata_file.path, events_metadata_path, args.verbose)  # type: ignore
    else:
        events_metadata_path = events_metadata_file.path

    _, dataset_tag_dict = insert_events_metadata_file(env, DatasetSource(project_id), events_metadata_file)

    return dataset_tag_dict


def insert_events_metadata_file(
    env: Env,
    source: EventFileSource,
    events_dictionary_file: BidsJsonFile,
):
    """
    Inserts the events metadata information read from the file *events.json
    into the physiological_event_file, physiological_event_parameter
    and physiological_event_parameter_category_level tables, linking it to the
    physiological file ID already inserted in physiological_file.
    """

    event_file = DbPhysioEventFile(
        physio_file_id = source.physio_file_id,
        project_id     = source.project_id,
        type           = 'json',
        path           = events_dictionary_file.path,
    )

    env.db.add(event_file)
    env.db.flush()

    tag_dict: dict[str, dict[str, list[TagGroupMember]]] = {}
    for event_name, event in events_dictionary_file.data.items():
        tag_dict[event_name] = parse_event_description(env, source, event_name, event)

    if source.physio_file is not None:
        # get the blake2b hash of the task events file
        blake2 = compute_file_blake2b_hash(events_dictionary_file.path)

        # insert blake2b hash of task event file into physiological_parameter_file
        insert_physio_file_parameter(env, source.physio_file, 'event_file_json_blake2b_hash', blake2)
        env.db.flush()

    return event_file.id, tag_dict


def parse_event_description(
    env: Env,
    source: EventFileSource,
    event_name: str,
    event: Any,
) -> dict[str, list[TagGroupMember]]:
    """
    Parse and insert the HED tags of an event dictionary file.
    """

    if event['Levels'] is None:
        return {}

    tag_dict: dict[str, list[TagGroupMember]] = {}
    for level_name, level in event['Levels'].items():
        tag_dict[level_name] = []
        level_hed = event['HED'][level_name] \
            if isinstance(event['HED'], dict) and level in event['HED'] \
            else None

        if level_hed is not None:
            tag_groups = build_hed_tag_groups(env, level_hed)
            insert_hed_tag_group(env, source, tag_groups, event_name, level_name, str(level))
            tag_dict[level_name] = tag_groups

    return tag_dict
