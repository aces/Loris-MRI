from dataclasses import dataclass

from lib.db.models.bids_event_dataset_mapping import DbBidsEventDatasetMapping
from lib.db.models.bids_event_file_mapping import DbBidsEventFileMapping
from lib.db.models.hed_schema_node import DbHedSchemaNode
from lib.db.queries.hed_schema_node import get_all_hed_schema_nodes
from lib.env import Env
from lib.physio.events import DatasetSource, EventFileSource, FileSource
from lib.physiological import Physiological
from lib.util.iter import find


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


def build_hed_tag_groups(
    env: Env,
    hed_string: str,
) -> list[TagGroupMember]:
    """
    Assembles physiological event HED tags.
    :return                     : List of HEDTagID groups
        :rtype                     : list[TagGroupMember]
    """
    # TODO: VALIDATE HED TAGS VIA SERVICE
    # hedDict = utilities.assemble_hed_service(data_dir, event_tsv, event_json)

    # NOT SUPPORTED: DEFS & VALUES

    # TODO: TRANSACTION THAT ROLLS BACK IF HED_TAG_ID LIST MATCHES (CONSIDER ADDING ADDITIONAL + HP TO IT)

    string_split = hed_string.split(',')
    group_depth = 0
    tag_groups: list[TagGroupMember] = []
    tag_group: list[TagGroupMember] = []

    for element_index, split_element in enumerate(string_split.__reversed__()):
        additional_members = 0
        if group_depth == 0:
            if len(tag_group) > 0:
                tag_groups.append(tag_group)
                tag_group = []

        element = split_element.strip()
        right_stripped = element.rstrip(')')
        left_stripped = right_stripped.lstrip('(')
        num_opening_parentheses = len(right_stripped) - len(left_stripped)

        has_pairing = element.startswith('(') and (
            group_depth == 0 or not element.endswith(')')
        )

        if has_pairing:
            additional_members = \
                Physiological.get_additional_members_from_parenthesis_index(string_split, 1, element_index)

        hed_tag = get_hed_tag_id_from_name(env, left_stripped)
        tag_group.append(Physiological.TagGroupMember(hed_tag.id, has_pairing, additional_members))

        for i in range(
            0 if group_depth > 0 and element.startswith('(') and element.endswith(')') else 1,
            num_opening_parentheses
        ):
            has_pairing = True
            additional_members = \
                Physiological.get_additional_members_from_parenthesis_index(string_split, i + 1, element_index)
            tag_group.append(Physiological.TagGroupMember(None, has_pairing, additional_members))
        group_depth += (len(element) - len(right_stripped))
        group_depth -= num_opening_parentheses
    if len(tag_group) > 0:
        tag_groups.append(tag_group)

    return tag_groups


def get_hed_tag_id_from_name(env: Env, tag_string: str) -> DbHedSchemaNode:
    hed_schema_nodes = get_all_hed_schema_nodes(env.db)
    leaf_node = tag_string.split('/')[-1]  # LIMITED SUPPORT FOR NOW - NO VALUES OR DEFS
    hed_tag = find(lambda hed_tag: hed_tag.name == leaf_node, hed_schema_nodes)
    if hed_tag is None:
        print(f'ERROR: UNRECOGNIZED HED TAG: {tag_string}')
        raise

    return hed_tag


def insert_hed_tag_group(
    source: EventFileSource,
    hed_tag_group: list[TagGroupMember],
    property_name: str | None,
    property_value: str | None,
    level_description: str | None,
):
    """
    Assembles physiological event HED tags.

    :param hed_tag_group        : List of TagGroupMember to insert
        :type hed_tag_group        : list[TagGroupMember]

    :param target_id            : ProjectID if project_wide else PhysiologicalEventFileID
        :type target_id            : int

    :param property_name        : PropertyName
        :type property_name        : str | None

    :param property_value       : PropertyValue
        :type property_value       : str | None

    :param level_description    : Tag Description
        :type level_description    : str | None

    :param from_sidecar         : Whether tag comes from an events.json file
        :type from_sidecar         : bool

    :param project_wide         : Whether target is ProjectID or PhysiologicalEventFileID
        :type project_wide         : bool

    """
    pair_rel_id = None
    for hed_tag in hed_tag_group:
        match source:
            case DatasetSource():
                DbBidsEventDatasetMapping(
                    target_id=source.project_id,
                    property_name=property_name,
                    property_value=property_value,
                    hed_tag_id=hed_tag.hed_tag_id,
                    tag_value=hed_tag.tag_value,
                    has_pairing=hed_tag.has_pairing,
                    description=level_description,
                    pair_rel_id=pair_rel_id,
                    additional_members=hed_tag.additional_members,
                )
            case FileSource():
                DbBidsEventFileMapping(
                    target_id=source.project_id,
                    property_name=property_name,
                    property_value=property_value,
                    hed_tag_id=hed_tag.hed_tag_id,
                    tag_value=hed_tag.tag_value,
                    has_pairing=hed_tag.has_pairing,
                    description=level_description,
                    pair_rel_id=pair_rel_id,
                    additional_members=hed_tag.additional_members,
                )
