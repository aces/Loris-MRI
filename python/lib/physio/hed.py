import csv
import io
import re
from collections.abc import Sequence
from dataclasses import dataclass
from functools import reduce
from pathlib import Path
from typing import Any

import requests
from loris_utils.iter import find

from lib.db.models.hed_schema_node import DbHedSchemaNode


@dataclass
class TagGroupMember:
    hed_tag_id: int | None
    has_pairing: bool
    additional_members: int
    tag_value: str | None = None

    def __eq__(self, other: object):
        if not isinstance(other, TagGroupMember):
            return False

        return (
            self.hed_tag_id == other.hed_tag_id
            and self.has_pairing == other.has_pairing
            and self.additional_members == other.additional_members
        )


def get_additional_members_from_parenthesis_index(
    string_split: list[str],
    parentheses_to_find: int,
    end_index: int,
) -> int:
    """
    Helper method for determining AdditionalMembers for DB insert

    :param string_split        : String array to search
    :param parentheses_to_find : Number of closing parentheses to find
    :param end_index           : Current array index, to look back from

    :return                    : Number of additional members in group
    """

    left_to_find = parentheses_to_find
    sub_string_split = string_split[(len(string_split) - end_index - 1):]
    additional_members = 0

    for element_index, split_element in enumerate(sub_string_split):
        left_to_find -= split_element.count(')')
        left_to_find += split_element.count('(') if element_index > 0 else 0
        if left_to_find == 1 and split_element.endswith(')'):
            additional_members += 1
        if left_to_find < 1:
            return additional_members
    return 0


def build_hed_tag_groups(hed_union: Sequence[DbHedSchemaNode], hed_string: str) -> list[list[TagGroupMember]]:
    """
    Assembles physiological event HED tags.

    :param hed_union : Union of HED schemas
    :param hed_string: HED string

    :return: List of HEDTagID groups
    """
    # TODO: VALIDATE HED TAGS VIA SERVICE
    # hedDict = utilities.assemble_hed_service(data_dir, event_tsv, event_json)

    # NOT SUPPORTED: DEFS & VALUES

    # TODO: TRANSACTION THAT ROLLS BACK IF HED_TAG_ID LIST MATCHES (CONSIDER ADDING ADDITIONAL
    # + HP TO IT)

    string_split = hed_string.split(',')
    group_depth = 0
    tag_groups: list[list[TagGroupMember]] = []
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
                get_additional_members_from_parenthesis_index(string_split, 1, element_index)

        hed_tag_id = get_hed_tag_id_from_name(left_stripped, hed_union)
        tag_group.append(TagGroupMember(hed_tag_id, has_pairing, additional_members))

        for i in range(
            0 if group_depth > 0 and element.startswith('(') and element.endswith(')') else 1,
            num_opening_parentheses
        ):
            has_pairing = True
            additional_members = \
                get_additional_members_from_parenthesis_index(string_split, i + 1, element_index)
            tag_group.append(TagGroupMember(None, has_pairing, additional_members))
        group_depth += (len(element) - len(right_stripped))
        group_depth -= num_opening_parentheses
    if len(tag_group) > 0:
        tag_groups.append(tag_group)

    return tag_groups


def standardize_row_columns(row: dict[str, str | None]) -> dict[str, str | None]:
    """
    Standardizes LORIS-recognized events.tsv columns to their DB column name

    :param row: A row item from the events.tsv

    :return: Standardized row
    """

    standardized_row: dict[str, Any] = {}
    recognized_event_fields = [
        'Onset', 'Duration', 'TrialType',
        'ResponseTime', 'EventCode',
        'EventSample', 'EventType'
    ]
    for column_name, column_value in row.items():
        if column_value is None:
            continue

        stripped_name = column_name.replace('_', '')
        try:
            field_index = list(map(lambda f: f.lower(), recognized_event_fields)).index(stripped_name)
            column = recognized_event_fields[field_index]
        except ValueError:
            column = 'EventValue' if (column_name == 'value' or column_name == 'event_value') else column_name
        standardized_row[column] = column_value

    return standardized_row


def filter_inherited_tags(
    row: dict[str, str | None],
    tag_groups: list[list[TagGroupMember]],
    dataset_tag_dict: dict[str, Any],
    file_tag_dict: dict[str, Any],
) -> list[list[TagGroupMember]]:
    """
    Filters for tags inherited from events.json

    :param row             :  A row item from the events.tsv
    :param tag_groups      : Tag groups to filter
    :param dataset_tag_dict: Dict of dataset-inherited HED tags
    :param file_tag_dict   : Dict of subject-inherited HED tags

    :return: List of tag groups not inherited from events.json
    """
    # TODO: Overwrite dataset tags with file tags
    # Only dataset tags currently supported until overwrite
    standardized_row = standardize_row_columns(row)
    inherited_tag_groups = reduce(lambda a, b: a + b, [
        dataset_tag_dict[column_name][standardized_row[column_name]]
        for column_name in standardized_row
        if column_name in dataset_tag_dict
        and standardized_row[column_name] in dataset_tag_dict[column_name]
    ], [])
    return list(filter(
        lambda tag_group: not any(
            len(tag_group) == len(inherited_tag_group) and all(
                tag_group[i] == inherited_tag_group[i]
                for i in range(len(tag_group))
            )
            for inherited_tag_group in inherited_tag_groups
        ),
        tag_groups
    ))


def get_hed_tag_id_from_name(tag_string: str, hed_union: Sequence[DbHedSchemaNode]) -> int | None:
    leaf_node = tag_string.split('/')[-1]  # LIMITED SUPPORT FOR NOW - NO VALUES OR DEFS
    if len(tag_string) > 0:
        hed_tag = find(hed_union, lambda tag: tag.name == leaf_node)
        if hed_tag is None:
            print(f'ERROR: UNRECOGNIZED HED TAG: {tag_string}')
            raise

        return hed_tag.id

    return None


def assemble_hed_service(data_dir_path: Path, event_tsv_path: Path, event_json_path: Path):
    # Using HED Tool Rest Services to assemble the HED Tags
    # https://hed-examples.readthedocs.io/en/latest/HedToolsOnline.html#hed-restful-services

    # Request CSRF Token & session cookie
    request_token_url = 'https://hedtools.ucsd.edu/hed/services'
    token_response = requests.get(request_token_url)

    cookie = token_response.headers['Set-Cookie']
    token_match = re.search(r'csrf_token" value="(.+?)"', token_response.text)
    if token_match is None:
        raise Exception("No CSRF token found.")

    token = token_match.group(1)

    # Define headers for assemble POST request, containing token and cookie
    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRFToken": token,
        "Cookie": cookie
    }

    # Read event files as str
    event_json_text = open(data_dir_path / event_json_path).read()
    event_tsv_text = open(data_dir_path / event_tsv_path).read()

    # Define request parameters
    params = {
        'service': 'events_assemble',
        'schema_version': '8.0.0',
        'json_string': event_json_text,
        'events_string': event_tsv_text,
        'check_for_warnings': 'off',
        'expand_defs': 'on',
        'columns_included': ['onset']
    }

    # Make the request to assemble
    request_assemble_url = 'https://hedtools.ucsd.edu/hed/services_submit'
    assemble_response = requests.post(
        request_assemble_url, headers=headers, json=params
    )

    # get assembled results as dictionary
    data = assemble_response.json()['results']['data']
    results = list(csv.DictReader(io.StringIO(data), delimiter='\t'))

    return results
