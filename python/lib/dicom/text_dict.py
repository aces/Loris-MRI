from lib.dicom.text import write_value


class DictWriter:
    """
    Writer for a text dictionary, i.e, a text of the form:

    Key 1 : Value 1
    Key 2 : Value 2
    ...
    """

    def __init__(self, entries: list[tuple[str, str | int | float | None]]):
        self.entries = entries

    def get_keys_length(self):
        """
        Get the maximal length of the keys, used for padding
        """
        length = 0
        for entry in self.entries:
            key = entry[0]
            if len(key) > length:
                length = len(key)

        return length

    def write(self):
        """
        Serialize the text dictionary into a string
        """

        if not self.entries:
            return '\n'

        length = self.get_keys_length()

        entries = map(
            lambda entry: f'* {entry[0].ljust(length)} :   {write_value(entry[1])}\n',
            self.entries,
        )

        return ''.join(entries)
