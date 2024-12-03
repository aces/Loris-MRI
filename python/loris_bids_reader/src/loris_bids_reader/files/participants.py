from pathlib import Path
from typing import Any

import dateutil.parser
from dateutil.parser import ParserError
from lib.util.iter import find, replace_or_append

from loris_bids_reader.tsv import BidsTsvFile, BidsTsvRow


class BidsParticipantTsvRow(BidsTsvRow):
    """
    Class representing a BIDS participants.tsv row.

    Documentation: https://bids-specification.readthedocs.io/en/stable/modality-agnostic-files/data-summary-files.html#participants-file
    """

    participant_id: str
    birth_date: str | None
    cohort: str | None

    def __init__(self, data: dict[str, Any]):
        super().__init__(data)
        self.participant_id = data['participant_id'].removeprefix('sub-')
        self.birth_date = _read_birth_date(data)
        self.cohort = _read_cohort(data)


class BidsParticipantsTsvFile(BidsTsvFile[BidsParticipantTsvRow]):
    """
    Class representing a BIDS participants.tsv file.

    Documentation: https://bids-specification.readthedocs.io/en/stable/modality-agnostic-files/data-summary-files.html#participants-file
    """

    def __init__(self, path: Path):
        super().__init__(BidsParticipantTsvRow, path)

    def get_row(self, participant_id: str) -> BidsParticipantTsvRow | None:
        return find(self.rows, lambda row: row.participant_id == participant_id)

    def set_row(self, participant: BidsParticipantTsvRow):
        replace_or_append(self.rows, participant, lambda row: row.participant_id == participant.participant_id)

    def merge(self, other: 'BidsParticipantsTsvFile'):
        """
        Copy another `participants.tsv` file into this file. The rows of this file are replaced by
        those of the other file if there are duplicates.
        """

        for other_row in other.rows:
            self.set_row(other_row)


def _read_birth_date(data: dict[str, str]) -> str | None:
    """
    Read the date of birth field of a participant from a `participants.tsv` row.
    """

    for birth_date_field_ame in ['date_of_birth', 'birth_date', 'dob']:
        if birth_date_field_ame in data:
            try:
                return dateutil.parser.parse(data[birth_date_field_ame]).strftime('%Y-%m-%d')
            except ParserError:
                pass

    return None


def _read_cohort(data: dict[str, str]) -> str | None:
    """
    Read the cohort field of a participant from a `participants.tsv` row.
    """

    for cohort_field_name in ['cohort', 'subproject']:
        if cohort_field_name in data:
            return data[cohort_field_name]

    return None
