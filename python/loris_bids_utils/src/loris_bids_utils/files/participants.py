from typing import Self

from loris_utils.iter import find, replace_or_append

from loris_bids_utils.tsv import BidsTsvFile, BidsTsvRow


class BidsParticipantTsvRow(BidsTsvRow):
    """
    Class representing a BIDS participants.tsv row.

    Custom columns are preserved in ``data`` for callers to interpret.

    Documentation: https://bids-specification.readthedocs.io/en/stable/modality-agnostic-files/data-summary-files.html#participants-file
    """

    participant_id: str
    sex: str | None

    def __init__(self, data: dict[str, str | None]):
        super().__init__(data)
        participant_id = self.data.get('participant_id')
        if participant_id is None:
            raise Exception("Missing participant_id field in `participants.tsv` file.")

        self.participant_id = participant_id.removeprefix('sub-')
        self.sex = self.data.get('sex')

    def with_participant_id(self, participant_id: str) -> Self:
        """
        Return a copy of this row with a different participant ID.
        """

        participant_id = participant_id.removeprefix('sub-')
        data = dict(self.data)
        data['participant_id'] = f'sub-{participant_id}'
        return type(self)(data)


class BidsParticipantsTsvFile(BidsTsvFile[BidsParticipantTsvRow]):
    """
    Class representing a BIDS `participants.tsv` file.

    Documentation: https://bids-specification.readthedocs.io/en/stable/modality-agnostic-files/data-summary-files.html#participants-file
    """

    row_type = BidsParticipantTsvRow

    def get_row(self, participant_id: str) -> BidsParticipantTsvRow | None:
        """
        Get the row corresponding to the given participant ID.
        """

        return find(self.rows, lambda row: row.participant_id == participant_id)

    def set_row(self, participant: BidsParticipantTsvRow):
        """
        Add a row in the `participants.tsv` file, replacing it if a row already exists for its
        participant ID.
        """

        replace_or_append(self.rows, participant, lambda row: row.participant_id == participant.participant_id)

    def merge(self, other: 'BidsParticipantsTsvFile'):
        """
        Copy another `participants.tsv` file into this file. The rows of this file are replaced by
        those of the other file if there are duplicates.
        """

        for other_row in other.rows:
            self.set_row(other_row)
