from lib.import_dicom_study.text import write_value


class TableWriter:
    """
    Writer for a text table, that is, a table of the form:

    Field 1 | Field 2 | Field 3
    Value 1 | Value 2 | Value 3
    Value 4 | Value 5 | Value 6
    ...
    """

    rows: list[list[str]]

    def __init__(self):
        self.rows = []

    def get_cells_lengths(self):
        """
        Get the longest value length of each column, used for padding.
        """

        lengths = [0] * len(self.rows[0])
        for row in self.rows:
            for i in range(len(row)):
                if len(row[i]) > lengths[i]:
                    lengths[i] = len(row[i])

        return lengths

    def append_row(self, cells: list[str | int | float | None]):
        """
        Add a row to the table, which can be either the header or some values.
        """

        self.rows.append(list(map(write_value, cells)))

    def write(self):
        """
        Serialize the text table into a string.
        """

        if not self.rows:
            return '\n'

        lengths = self.get_cells_lengths()

        rows = map(lambda row: list(map(lambda cell, length: cell.ljust(length), row, lengths)), self.rows)
        rows = map(lambda row: ' | '.join(row).rstrip() + '\n', rows)

        return ''.join(rows)
