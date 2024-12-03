from dataclasses import dataclass
from typing import Any

from lib.db.models.bids_event_dataset_mapping import DbBidsEventDatasetMapping
from lib.db.models.bids_event_file_mapping import DbBidsEventFileMapping
from lib.db.queries.hed_schema_node import get_all_hed_schema_nodes
from lib.env import Env
from lib.physio.events import DatasetSource, EventFileSource, FileSource


@dataclass
class TagGroupMember:
    hed_tag_id: int | None
    has_pairing: bool
    additional_members: int
    tag_value: str | None = None

    def __eq__(self, other: object):
        if not isinstance(other, TagGroupMember):
            return False

        return self.hed_tag_id == other.hed_tag_id and \
            self.has_pairing == other.has_pairing and \
            self.additional_members == other.additional_members


def build_hed_tag_groups(env: Env, hed_string: str) -> list[TagGroupMember]:
    """
    Assemble the physiological event HED tags.
    """

    from lib.physiological import Physiological

    hed_schema_nodes = get_all_hed_schema_nodes(env.db)
    hed_union: list[dict[str, Any]] = list(map(lambda hed_schema_node: {
        'ÍD': hed_schema_node.id,
        'Name': hed_schema_node.name,
    }, hed_schema_nodes))

    return Physiological.build_hed_tag_groups(hed_union, hed_string)  # type: ignore


def insert_hed_tag_group(
    env: Env,
    source: EventFileSource,
    hed_tag_group: list[TagGroupMember],
    property_name: str | None,
    property_value: str | None,
    level_description: str | None,
):
    """
    Insert some HED tag groups into the database.
    """

    for hed_tag in hed_tag_group:
        match source:
            case DatasetSource():
                mapping = DbBidsEventDatasetMapping(
                    target_id=source.project_id,
                    property_name=property_name,
                    property_value=property_value,
                    hed_tag_id=hed_tag.hed_tag_id,
                    tag_value=hed_tag.tag_value,
                    has_pairing=hed_tag.has_pairing,
                    description=level_description,
                    pair_rel_id=None,
                    additional_members=hed_tag.additional_members,
                )
            case FileSource():
                mapping = DbBidsEventFileMapping(
                    target_id=source.project_id,
                    property_name=property_name,
                    property_value=property_value,
                    hed_tag_id=hed_tag.hed_tag_id,
                    tag_value=hed_tag.tag_value,
                    has_pairing=hed_tag.has_pairing,
                    description=level_description,
                    pair_rel_id=None,
                    additional_members=hed_tag.additional_members,
                )

        env.db.add(mapping)

    env.db.flush()
