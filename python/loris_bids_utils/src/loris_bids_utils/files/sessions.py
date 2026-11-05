from typing import Self

from loris_utils.iter import find, replace_or_append

from loris_bids_utils.tsv import BidsTsvFile, BidsTsvRow


class BidsSessionTsvRow(BidsTsvRow):
    """
    Class representing a BIDS sessions.tsv row.

    Documentation: https://bids-specification.readthedocs.io/en/stable/modality-agnostic-files/data-summary-files.html#sessions-file
    """

    session_id: str

    def __init__(self, data: dict[str, str | None]):
        super().__init__(data)
        session_id = self.data.get('session_id')
        if session_id is None:
            raise Exception("Missing session_id field in `sessions.tsv` file.")

        self.session_id = session_id.removeprefix('ses-')

    def with_session_id(self, session_id: str) -> Self:
        """
        Return a copy of this row with a different session ID.
        """

        session_id = session_id.removeprefix('ses-')
        data = dict(self.data)
        data['session_id'] = f'ses-{session_id}'
        return type(self)(data)


class BidsSessionsTsvFile(BidsTsvFile[BidsSessionTsvRow]):
    """
    Class representing a BIDS sessions.tsv file.

    Documentation: https://bids-specification.readthedocs.io/en/stable/modality-agnostic-files/data-summary-files.html#sessions-file
    """

    row_type = BidsSessionTsvRow

    def get_row(self, session_id: str) -> BidsSessionTsvRow | None:
        """
        Get the row corresponding to the given session ID.
        """

        return find(self.rows, lambda row: row.session_id == session_id.removeprefix('ses-'))

    def set_row(self, session: BidsSessionTsvRow):
        """
        Add a row, replacing an existing row with the same session ID.
        """

        replace_or_append(self.rows, session, lambda row: row.session_id == session.session_id)

    def merge(self, other: 'BidsSessionsTsvFile'):
        """
        Copy rows from another sessions file, replacing duplicate rows.
        """

        for other_row in other.rows:
            self.set_row(other_row)
