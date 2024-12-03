from decimal import Decimal
from pathlib import Path
from typing import Any

from loris_bids_reader.files.events import OPTIONAL_EVENT_FIELDS, BidsEventsTsvFile
from loris_bids_reader.json import BidsJsonFile
from loris_utils.crypto import compute_file_blake2b_hash

from lib.db.models.physio_event_file import DbPhysioEventFile
from lib.db.models.physio_file import DbPhysioFile
from lib.db.models.project import DbProject
from lib.env import Env
from lib.import_bids_dataset.copy_files import copy_loris_bids_file, get_loris_bids_root_file_path
from lib.import_bids_dataset.env import BidsImportEnv
from lib.physio.events import (
    EventDictFileSource,
    insert_event_dict_file,
    insert_events_file,
    insert_physio_task_event,
    insert_physio_task_event_hed,
    insert_physio_task_event_opt,
    parse_and_insert_event_dict,
)
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


# TODO: This function contains a lot of legacy code and needs to be refactored.
def insert_bids_events_file(
    env: Env,
    physio_file: DbPhysioFile,
    events_file: BidsEventsTsvFile,
    loris_events_file_path: Path,
    dataset_tag_dict: dict[str, Any],
    file_tag_dict: dict[str, Any],
    hed_union: list[dict[str, Any]],
):
    """
    Inserts the event information read from the file *events.tsv
    into the physiological_task_event table, linking it to the
    physiological file ID already inserted in physiological_file.
    Only called in `eeg.py`.

    :param dataset_tag_dict     : Dict of dataset-inherited HED tags
     :type dataset_tag_dict     : dict
    :param file_tag_dict        : Dict of subject-inherited HED tags
     :type file_tag_dict        : dict
    :param hed_union            : Union of HED schemas
     :type hed_union            : any
    """

    blake2_hash = compute_file_blake2b_hash(events_file.path)

    event_file = insert_events_file(env, physio_file, loris_events_file_path)

    # insert blake2b hash of task event file into physiological_parameter_file
    insert_physio_file_parameter(env, physio_file, 'event_file_blake2b_hash', blake2_hash)

    event_fields = (
        'PhysiologicalFileID', 'Onset',     'Duration',   'TrialType',
        'ResponseTime',        'EventCode', 'EventValue', 'EventSample',
        'EventType',           'FilePath',  'EventFileID'
    )

    # all listed fields
    known_fields = {*event_fields, *OPTIONAL_EVENT_FIELDS}

    for row in events_file.rows:
        # has additional fields?
        additional_fields: dict[str, str] = {}
        for field in row.data:
            if field not in known_fields and str(row.data[field]).lower() != 'nan':
                additional_fields[field] = row.data[field]

        # insert one event and get its db id
        task_event = insert_physio_task_event(
            env,
            physio_file,
            event_file,
            row.onset or Decimal(0),
            row.duration or Decimal(0),
            row.event_code,
            row.event_value,
            row.event_sample,
            row.event_type,
            row.trial_type,
            row.response_time,
        )

        # Insert HED tags after filtering out inherited tags from events.json, so that they are
        # not "duplicated"
        if row.data.get('HED') is not None and len(row.data['HED']) > 0 and row.data['HED'] != 'n/a':
            tag_groups = Physiological.build_hed_tag_groups(hed_union, row.data['HED'])  # type: ignore
            tag_groups_without_inherited = Physiological.filter_inherited_tags(  # type: ignore
                row.data, tag_groups, dataset_tag_dict, file_tag_dict
            )
            for tag_group in tag_groups_without_inherited:  # type: ignore
                for tag_member in tag_group:  # type: ignore
                    insert_physio_task_event_hed(env, task_event, tag_member)  # type: ignore

        # if needed, process additional and unlisted
        # fields and send them in secondary table
        if additional_fields:
            # each additional fields is a new entry
            for add_field, add_value in additional_fields.items():
                insert_physio_task_event_opt(env, task_event, add_field, add_value)
