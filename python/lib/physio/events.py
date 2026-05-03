from dataclasses import dataclass
from pathlib import Path
from typing import Any

from lib.db.queries.hed_schema_node import get_all_hed_schema_nodes

from lib.db.models.bids_event_dataset_mapping import DbBidsEventDatasetMapping
from lib.db.models.bids_event_file_mapping import DbBidsEventFileMapping
from lib.db.models.physio_event_file import DbPhysioEventFile
from lib.db.models.physio_file import DbPhysioFile
from lib.db.models.project import DbProject
from lib.env import Env
from lib.physiological import Physiological


@dataclass
class EventDictFileSource:
    """
    Class representing whether an event dictionary file is dataset-wide or comes from a specific acquisition.
    """

    project: DbProject
    physio_file: DbPhysioFile | None

    @staticmethod
    def from_dataset(project: DbProject) -> 'EventDictFileSource':
        """
        Create an event dictionary file source from dataset-wide information.
        """

        return EventDictFileSource(
            project = project,
            physio_file = None,
        )

    @staticmethod
    def from_file(physio_file: DbPhysioFile) -> 'EventDictFileSource':
        """
        Create an event dictionary file source from a specific acquisition file.
        """

        return EventDictFileSource(
            project = physio_file.session.project,
            physio_file = physio_file,
        )


def insert_event_dict_file(env: Env, source: EventDictFileSource, event_file_path: Path) -> DbPhysioEventFile:
    """
    Insert an event dictionary file into the LORIS database.
    """

    event_dict_file = DbPhysioEventFile(
        physio_file_id = source.physio_file.id if source.physio_file else None,
        project_id     = source.project.id,
        file_type      = 'json',
        file_path      = event_file_path,
    )

    env.db.add(event_dict_file)
    env.db.flush()
    return event_dict_file


def insert_bids_event_mapping(
    env: Env,
    source: EventDictFileSource,
    property_name: str,
    property_value: str,
    level_description: str,
    hed_tag_group: list[Physiological.TagGroupMember],
) -> None:
    """
    Insert BIDS event mappings into the LORIS database.
    """

    for hed_tag_member in hed_tag_group:
        if source.physio_file is None:
            insert_bids_dataset_event_mapping(
                env,
                source.project,
                property_name,
                property_value,
                level_description,
                hed_tag_member,
            )
        else:
            insert_bids_file_event_mapping(
                env,
                source.physio_file,
                property_name,
                property_value,
                level_description,
                hed_tag_member,
            )


def insert_bids_dataset_event_mapping(
    env: Env,
    project: DbProject,
    property_name: str,
    property_value: str,
    level_description: str,
    hed_tag_member: Physiological.TagGroupMember,
) -> DbBidsEventDatasetMapping:
    """
    Insert a dataset-wide BIDS event mapping into the LORIS database.
    """

    mapping = DbBidsEventDatasetMapping(
        project_id         = project.id,
        property_name      = property_name,
        property_value     = property_value,
        description        = level_description,
        hed_tag_id         = hed_tag_member.hed_tag_id,
        tag_value          = hed_tag_member.tag_value,
        has_pairing        = hed_tag_member.has_pairing,
        additional_members = hed_tag_member.additional_members
    )

    env.db.add(mapping)
    env.db.flush()
    return mapping


def insert_bids_file_event_mapping(
    env: Env,
    physio_file: DbPhysioFile,
    property_name: str,
    property_value: str,
    level_description: str,
    hed_tag_member: Physiological.TagGroupMember,
) -> DbBidsEventFileMapping:
    """
    Insert a acquisition-specific BIDS event mapping into the LORIS database.
    """

    mapping = DbBidsEventFileMapping(
        event_file_id      = physio_file.id,
        property_name      = property_name,
        property_value     = property_value,
        description        = level_description,
        hed_tag_id         = hed_tag_member.hed_tag_id,
        tag_value          = hed_tag_member.tag_value,
        has_pairing        = hed_tag_member.has_pairing,
        additional_members = hed_tag_member.additional_members
    )

    env.db.add(mapping)
    env.db.flush()
    return mapping


def parse_and_insert_event_dict(
    env: Env,
    event_dict: dict[str, Any],
    source: EventDictFileSource,
) -> dict[str, dict[str, list[list[Physiological.TagGroupMember]]]]:
    """
    Parse a BIDS event dictionary and insert its mappings into the LORIS database.
    """

    # This function uses a lot of legacy code and is copied from the `Physiological` class.

    hed_schema_nodes = get_all_hed_schema_nodes(env.db)

    # Format the HED nodes to be compatible with the legacy HED reader.
    hed_union: list[dict[str, Any]] = list(map(lambda node: {
        'ID': node.id,
        'Name': node.name,
    }, hed_schema_nodes))

    tag_dict: dict[str, dict[str, list[list[Physiological.TagGroupMember]]]] = {}

    for event_name, event in event_dict.items():
        tag_dict[event_name] = {}
        # TODO: Commented fields below currently not supported # ruff: noqa
        # description = event_metadata[parameter]['Description'] \
        #     if 'Description' in event_metadata[parameter] \
        #     else None
        # long_name = event_metadata[parameter]['LongName'] if 'LongName' in event_metadata[parameter] else None
        # units = event_metadata[parameter]['Units'] if 'Units' in event_metadata[parameter] else None
        if 'Levels' in event:
            is_categorical = 'Y'
            # value_hed = None
        else:
            is_categorical = 'N'
            # value_hed = event_metadata[parameter]['HED'] if 'HED' in event_metadata[parameter] else None

        if is_categorical == 'Y':
            for level in event['Levels']:
                level_name = level
                tag_dict[event_name][level_name] = []
                level_description = event['Levels'][level]
                level_hed = event['HED'][level] \
                    if 'HED' in event and level in event['HED'] \
                    else None

                if level_hed:
                    tag_groups: list[list[Physiological.TagGroupMember]] = Physiological.build_hed_tag_groups(hed_union, level_hed)  # type: ignore
                    for tag_group in tag_groups:
                        insert_bids_event_mapping(env, source, event_name, level_name, level_description, tag_group)
                    tag_dict[event_name][level_name] = tag_groups

    return tag_dict
