from datetime import date
from pathlib import Path

import dateutil.parser
from dateutil.parser import ParserError
from loris_utils.iter import find

from loris_bids_reader.tsv import BidsTsvFile, BidsTsvRow


class BidsParticipantTsvRow(BidsTsvRow):
    """
    Class representing a BIDS participants.tsv row.

    Documentation: https://bids-specification.readthedocs.io/en/stable/modality-agnostic-files/data-summary-files.html#participants-file
    """

    participant_id: str
    birth_date: date | None
    cohort: str | None

    def __init__(self, data: dict[str, str]):
        super().__init__(data)
        self.participant_id = data['participant_id'].removeprefix('sub-')
        self.birth_date = self._read_birth_date()
        self.cohort = self._read_cohort()

    def _read_birth_date(self) -> date | None:
        """
        Read the date of birth field from this row data.
        """

        for birth_date_field_name in ['date_of_birth', 'birth_date', 'dob']:
            if birth_date_field_name in self.data:
                try:
                    return dateutil.parser.parse(self.data[birth_date_field_name]).date()
                except ParserError:
                    pass

        return None

    def _read_cohort(self) -> str | None:
        """
        Read the cohort field from this row data..
        """

        for cohort_field_name in ['cohort', 'subproject']:
            if cohort_field_name in self.data:
                return self.data[cohort_field_name]

        return None


class BidsParticipantsTsvFile(BidsTsvFile[BidsParticipantTsvRow]):
    """
    Class representing a BIDS participants.tsv file.

    Documentation: https://bids-specification.readthedocs.io/en/stable/modality-agnostic-files/data-summary-files.html#participants-file
    """

    def __init__(self, path: Path):
        super().__init__(BidsParticipantTsvRow, path)

    def get_row(self, participant_id: str) -> BidsParticipantTsvRow | None:
        """
        Get the row corresponding to the given participant ID.
        """

        return find(self.rows, lambda row: row.participant_id == participant_id)
