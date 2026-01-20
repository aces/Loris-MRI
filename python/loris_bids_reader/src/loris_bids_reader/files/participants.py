from pathlib import Path

from lib.util.iter import find

from loris_bids_reader.tsv import BidsTsvFile, BidsTsvRow


class BidsParticipantTsvRow(BidsTsvRow):
    """
    Class representing a BIDS participants.tsv row.

    Documentation: https://bids-specification.readthedocs.io/en/stable/modality-agnostic-files/data-summary-files.html#participants-file
    """

    pass


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

        return find(self.rows, lambda row: row.data['participant_id'] == participant_id)
