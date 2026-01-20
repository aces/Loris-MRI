from pathlib import Path

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

        # TODO: Replace with `lib.util.iter.find` once the parameters order is stabilized.
        for row in self.rows:
            if participant_id == row.data['participant_id']:
                return row

        return None
