import csv
import re
from dataclasses import dataclass
from pathlib import Path

from dateutil.parser import ParserError, parse


@dataclass
class BidsTsvParticipant:
    """
    Information about a participant found in a row of the `participants.tsv` file of a BIDS
    dataset.
    """

    id:         str
    birth_date: str | None = None
    sex:        str | None = None
    age:        str | None = None
    site:       str | None = None
    cohort:     str | None = None
    project:    str | None = None


def read_bids_participants_tsv_file(participants_tsv_path: Path) -> dict[str, BidsTsvParticipant]:
    """
    Read the `participants.tsv` file of a BIDS dataset and get the participant rows indexed by
    participant ID. Raise an exception if the `participants.tsv` file is incorrect.
    """

    tsv_participants: dict[str, BidsTsvParticipant] = {}
    with open(participants_tsv_path) as participants_tsv_file:
        reader = csv.DictReader(participants_tsv_file.readlines(), delimiter='\t')
        if reader.fieldnames is None or 'participant_id' not in reader.fieldnames:
            raise Exception(f"Missing 'participant_id' field in participants.tsv file '{participants_tsv_path}'.")

        for tsv_participant_row in reader:
            tsv_participant = read_bids_participants_tsv_row(tsv_participant_row, participants_tsv_path)
            tsv_participants[tsv_participant.id] = tsv_participant

    return tsv_participants


def read_bids_participants_tsv_row(
    tsv_participant_row: dict[str, str],
    participants_tsv_path: Path,
) -> BidsTsvParticipant:
    """
    Read a `participants.tsv` row, or raise an exception if that row is incorrect.
    """

    # Get the participant ID and removing the `sub-` prefix if it is present.
    full_participant_id = tsv_participant_row.get('participant_id')
    if full_participant_id is None:
        raise Exception(f"Missing 'participant_id' value in participants.tsv file '{participants_tsv_path}'.")

    participant_id = re.sub(r'^sub-', '', full_participant_id)

    birth_date = _read_birth_date(tsv_participant_row)
    cohort     = _read_cohort(tsv_participant_row)

    # Create the BIDS participant object.
    return BidsTsvParticipant(
        id         = participant_id,
        birth_date = birth_date,
        sex        = tsv_participant_row.get('sex'),
        age        = tsv_participant_row.get('age'),
        site       = tsv_participant_row.get('site'),
        project    = tsv_participant_row.get('project'),
        cohort     = cohort,
    )


def write_bids_participants_tsv_file(tsv_participants: dict[str, BidsTsvParticipant], participants_file_path: Path):
    """
    Write the `participants.tsv` file based from a set of participant rows.
    """

    with open(participants_file_path, 'w') as participants_file:
        writer = csv.writer(participants_file, delimiter='\t')
        writer.writerow(['participant_id'])

        for tsv_participant in sorted(tsv_participants.values(), key=lambda tsv_participant: tsv_participant.id):
            writer.writerow([tsv_participant.id])


def merge_bids_tsv_participants(
    tsv_participants: dict[str, BidsTsvParticipant],
    new_tsv_participants: dict[str, BidsTsvParticipant],
):
    """
    Copy a set of participants.tsv rows into another one. The rows of the first set are replaced by
    those of these second if there are duplicates.
    """

    for new_tsv_participant in new_tsv_participants.values():
        tsv_participants[new_tsv_participant.id] = new_tsv_participant


def _read_birth_date(tsv_participant_row: dict[str, str]) -> str | None:
    """
    Read the date of birth field of a participant from a `participants.tsv` row.
    """

    for birth_date_field_ame in ['date_of_birth', 'birth_date', 'dob']:
        if birth_date_field_ame in tsv_participant_row:
            try:
                return parse(tsv_participant_row[birth_date_field_ame]).strftime('%Y-%m-%d')
            except ParserError:
                pass

    return None


def _read_cohort(tsv_participant_row: dict[str, str]) -> str | None:
    """
    Read the cohort field of a participant from a `participants.tsv` row.
    """

    for cohort_field_name in ['cohort', 'subproject']:
        if cohort_field_name in tsv_participant_row:
            return tsv_participant_row[cohort_field_name]

    return None
