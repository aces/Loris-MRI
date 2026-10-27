"""Read and update strings in CTF CPersist binary data.

CPersist is a big-endian stream of typed, named values that can contain nested
CPersist objects.
"""

from collections.abc import Mapping
from enum import IntEnum
from typing import NewType

CPersistLabel = NewType('CPersistLabel', str)


class CPersistFormatError(ValueError):
    """Raised when serialized CPersist data does not match its specification."""


class ValueType(IntEnum):
    """Value types supported by the CPersist format."""

    CUSTOM = 1
    CPERSIST = 2
    BINARY = 3
    DOUBLE = 4
    INTEGER = 5
    SHORT = 6
    UNSIGNED_SHORT = 7
    BOOLEAN_CHAR = 8
    CSTR32 = 9
    CSTRING = 10
    CSTRING_LIST = 11
    CSTR32_LIST = 12
    SENSOR_CLASS_LIST = 13
    LONG = 14
    UNSIGNED_LONG = 15
    UNSIGNED_INTEGER = 16
    CTF_BOOLEAN = 17


START_MARKER = b'WS1_'
END_MARKER = CPersistLabel('EndOfParameters')
_DATASET_FILES_LABEL = CPersistLabel('DatasetFiles')


class CPersistReader:
    """Read primitive values from a CPersist stream with bounds checking."""

    def __init__(self, content: bytes):
        """Create a reader positioned at the first byte of `content`."""

        self._content = memoryview(content)
        self.position = 0

    @property
    def remaining(self) -> int:
        """Return the number of unread bytes in the stream."""

        return len(self._content) - self.position

    def read_bytes(self, size: int, description: str) -> bytes:
        """Read exactly `size` bytes and advance the cursor."""

        if size < 0:
            raise CPersistFormatError(f"Negative {description} size {size} at byte {self.position}")
        end = self.position + size
        if end > len(self._content):
            raise CPersistFormatError(
                f"Truncated {description} at byte {self.position}: need {size} bytes, only {self.remaining} remain"
            )
        value = bytes(self._content[self.position : end])
        self.position = end
        return value

    def read_int32(self, description: str) -> int:
        """Read one signed, big-endian 32-bit integer."""

        return int.from_bytes(
            self.read_bytes(4, description),
            byteorder='big',
            signed=True,
        )

    def read_text(self, size: int, description: str) -> str:
        """Read text without losing the byte representation used by the file."""

        return self.read_bytes(size, description).decode('latin-1')

    def read_label(self) -> CPersistLabel:
        """Read a length-prefixed CPersist label."""

        length = self.read_int32("tag label length")
        return CPersistLabel(self.read_text(length, "tag label"))

    def expect_bytes(self, expected: bytes, description: str):
        """Read a fixed marker and verify its value."""

        offset = self.position
        actual = self.read_bytes(len(expected), description)
        if actual != expected:
            raise CPersistFormatError(f"Expected {expected!r} at byte {offset}, found {actual!r}")


class CPersistWriter:
    """Build a CPersist byte stream from primitives in memory."""

    def __init__(self):
        """Create an empty output stream."""

        self._content = bytearray()

    def write_bytes(self, value: bytes):
        """Append `value` without interpreting or transforming it."""

        self._content.extend(value)

    def write_int32(self, value: int):
        """Append one signed integer using CPersist's big-endian 32-bit form."""

        self.write_bytes(value.to_bytes(4, byteorder='big', signed=True))

    def write_label(self, label: CPersistLabel):
        """Append a CPersist label with its byte length."""

        encoded = label.encode('latin-1')
        self.write_int32(len(encoded))
        self.write_bytes(encoded)

    def to_bytes(self) -> bytes:
        """Return an immutable copy of the serialized output."""

        return bytes(self._content)


def replace_strings(content: bytes, replacements: Mapping[str, str]) -> bytes:
    """Replace selected CString values while copying a CPersist object.

    The complete input is validated and rebuilt in memory before it is returned.
    Values not selected for replacement are preserved.
    """

    encoded_replacements = {
        CPersistLabel(label): _encode_replacement(label, replacement) for label, replacement in replacements.items()
    }

    reader = CPersistReader(content)
    writer = CPersistWriter()

    _copy_object(reader, writer, encoded_replacements)
    if reader.remaining:
        raise CPersistFormatError(f"Unexpected data after CPersist object at byte {reader.position}")

    return writer.to_bytes()


def _encode_replacement(label: str, replacement: str) -> bytes:
    """Encode a replacement using the text representation stored by CPersist."""

    try:
        return replacement.encode('latin-1')
    except UnicodeEncodeError as exc:
        raise ValueError(f"CPersist replacement must be Latin-1 for {label!r}: {replacement}") from exc


def _copy_object(reader: CPersistReader, writer: CPersistWriter, replacements: Mapping[CPersistLabel, bytes]):
    """Copy a CPersist object, including any nested objects."""

    reader.expect_bytes(START_MARKER, "CPersist start marker")
    writer.write_bytes(START_MARKER)

    while True:
        if not reader.remaining:
            raise CPersistFormatError(f"Unclosed CPersist object at byte {reader.position}")

        label = reader.read_label()
        writer.write_label(label)

        if label == END_MARKER:
            return

        type_offset = reader.position
        type_code = reader.read_int32(f"value type for {label!r}")
        writer.write_int32(type_code)

        try:
            value_type = ValueType(type_code)
        except ValueError as exc:
            raise CPersistFormatError(f"Unknown value type {type_code} for {label!r} at byte {type_offset}") from exc

        if value_type is ValueType.CSTRING:
            _replace_cstring(reader, writer, label, replacements)
        else:
            _copy_tag_value(reader, writer, label, value_type, replacements)


def _replace_cstring(
    reader: CPersistReader,
    writer: CPersistWriter,
    label: CPersistLabel,
    replacements: Mapping[CPersistLabel, bytes],
):
    """Copy a CString, replacing its value when its label is selected."""

    length = reader.read_int32(f"CString length for {label!r}")
    value = reader.read_bytes(length, f"CString value for {label!r}")
    replacement = replacements.get(label, value)
    writer.write_int32(len(replacement))
    writer.write_bytes(replacement)


def _copy_tag_value(
    reader: CPersistReader,
    writer: CPersistWriter,
    label: CPersistLabel,
    value_type: ValueType,
    replacements: Mapping[CPersistLabel, bytes],
):
    """Copy a tag value using the layout associated with its type."""

    match value_type:
        case ValueType.CUSTOM:
            # PN900-0088 leaves custom payloads type-specific. The readCPersist.m
            # bundled with the pinned port source treats only DatasetFiles as one
            # int32 and all other custom tags as having no payload:
            # https://github.com/Moo-Marc/CtfMegBids/blob/f550ecf776733f92d0855e294309b2a1e93a262d/BstDependencies/readCPersist.m
            if label == _DATASET_FILES_LABEL:
                _copy_bytes(reader, writer, 4, label)
        case ValueType.CPERSIST:
            # A nested object immediately follows as another WS1_...EndOfParameters
            # stream; type 2 itself has no value-length or payload field.
            _copy_object(reader, writer, replacements)
        case ValueType.BINARY:
            _copy_length_prefixed_bytes(reader, writer, label)
        case ValueType.DOUBLE:
            _copy_bytes(reader, writer, 8, label)
        case (
            ValueType.INTEGER
            | ValueType.LONG
            | ValueType.UNSIGNED_LONG
            | ValueType.UNSIGNED_INTEGER
            | ValueType.CTF_BOOLEAN
        ):
            _copy_bytes(reader, writer, 4, label)
        case ValueType.SHORT | ValueType.UNSIGNED_SHORT:
            _copy_bytes(reader, writer, 2, label)
        case ValueType.BOOLEAN_CHAR:
            _copy_bytes(reader, writer, 1, label)
        case ValueType.CSTR32:
            _copy_bytes(reader, writer, 32, label)
        case ValueType.CSTRING_LIST:
            count = _copy_list_count(reader, writer, label)
            for index in range(count):
                item_label = CPersistLabel(f'{label}[{index}]')
                _copy_length_prefixed_bytes(reader, writer, item_label)
        case ValueType.CSTR32_LIST:
            count = _copy_list_count(reader, writer, label)
            _copy_bytes(reader, writer, 32 * count, label)
        case ValueType.SENSOR_CLASS_LIST:
            count = _copy_list_count(reader, writer, label)
            _copy_bytes(reader, writer, 4 * count, label)
        case ValueType.CSTRING:
            raise AssertionError("CString values are handled separately")


def _copy_list_count(reader: CPersistReader, writer: CPersistWriter, label: CPersistLabel) -> int:
    """Copy and return the item count that precedes a CPersist list."""

    count = reader.read_int32(f"list count for {label!r}")
    if count < 0:
        raise CPersistFormatError(f"Negative list count {count} for {label!r} at byte {reader.position - 4}")
    writer.write_int32(count)
    return count


def _copy_length_prefixed_bytes(reader: CPersistReader, writer: CPersistWriter, label: CPersistLabel):
    """Copy a byte length followed by a payload of that length."""

    length = reader.read_int32(f"value length for {label!r}")
    writer.write_int32(length)
    _copy_bytes(reader, writer, length, label)


def _copy_bytes(reader: CPersistReader, writer: CPersistWriter, size: int, label: CPersistLabel):
    """Copy a fixed-size value payload without interpreting it."""

    writer.write_bytes(reader.read_bytes(size, f"value for {label!r}"))
