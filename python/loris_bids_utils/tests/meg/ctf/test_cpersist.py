import struct

import pytest

from loris_bids_utils.meg.ctf.cpersist import (
    CPersistFormatError,
    CPersistReader,
    CPersistWriter,
    replace_strings,
)

from ._synthetic import cstring, document, tag


def test_reader_reports_offset_for_truncated_value():
    reader = CPersistReader(b'\x00\x01')
    with pytest.raises(CPersistFormatError, match=r'byte 0.*only 2 remain'):
        reader.read_int32('test integer')


def test_writer_writes_big_endian_int32():
    writer = CPersistWriter()
    writer.write_int32(0x01020304)
    assert writer.to_bytes() == b'\x01\x02\x03\x04'


def test_reader_and_writer_handle_length_prefixed_labels():
    encoded = b'\x00\x00\x00\x05value'
    reader = CPersistReader(encoded)
    writer = CPersistWriter()
    label = reader.read_label()
    writer.write_label(label)
    assert label == 'value'
    assert writer.to_bytes() == encoded


# Literal type IDs and nonzero payloads come from Table 20, not ValueType.
# A selected string AFTER each value detects incorrect widths/cursor alignment.
WIRE_VALUES = [
    pytest.param(2, document(tag('nested', 5, struct.pack('>i', -123))), id='nested-object'),
    pytest.param(3, cstring(b'\x00\xffWS1_EndOfParametersold'), id='binary'),
    pytest.param(4, struct.pack('>d', -123.125), id='double'),
    pytest.param(5, struct.pack('>i', -123456), id='integer'),
    pytest.param(6, struct.pack('>h', -1234), id='short'),
    pytest.param(7, struct.pack('>H', 65535), id='unsigned-short'),
    pytest.param(8, b'\x01', id='boolean-char'),
    pytest.param(9, b'old'.ljust(32, b'\0'), id='cstr32'),
    pytest.param(10, cstring(b'old\0'), id='cstring'),
    pytest.param(11, struct.pack('>i', 2) + cstring(b'old') + cstring(b'two\0'), id='cstring-list'),
    pytest.param(12, struct.pack('>i', 2) + b'old'.ljust(32, b'\0') + b'two'.ljust(32, b'\0'), id='cstr32-list'),
    pytest.param(13, struct.pack('>iii', 2, 5, 20), id='sensor-class-list'),
    pytest.param(14, struct.pack('>i', -2147483648), id='long'),
    pytest.param(15, struct.pack('>I', 4294967295), id='unsigned-long'),
    pytest.param(16, struct.pack('>I', 2147483648), id='unsigned-integer'),
    pytest.param(17, struct.pack('>i', 1), id='ctf-boolean'),
]


@pytest.mark.parametrize(('type_code', 'payload'), WIRE_VALUES)
def test_replacing_string_preserves_other_typed_values(type_code: int, payload: bytes):
    preserved = tag('unselected', type_code, payload)
    original = document(preserved, tag('_PATIENT_ID', 10, cstring(b'old')))
    expected = document(preserved, tag('_PATIENT_ID', 10, cstring(b'sub-new')))

    assert replace_strings(original, {'_PATIENT_ID': 'sub-new'}) == expected
    assert replace_strings(original, {}) == original


@pytest.mark.parametrize('new_subject', ['', 'x', 'sub-Andr\xe9', 'a much longer identifier'])
def test_selected_cstring_lengths_are_recomputed_in_each_nested_object(new_subject: str):
    # Identical bytes in an unrelated field must not undergo global replacement.
    unrelated = tag('_DATASET_COMMENTS', 10, cstring(b'old'))

    def content(subject: bytes) -> bytes:
        return document(
            tag('_PATIENT_INFO', 2, document(tag('_PATIENT_ID', 10, cstring(subject)))),
            unrelated,
            tag('another-group', 2, document(tag('_PATIENT_ID', 10, cstring(subject)))),
        )

    assert replace_strings(content(b'old'), {'_PATIENT_ID': new_subject}) == content(new_subject.encode('latin-1'))


@pytest.mark.parametrize('type_code', [3, 9, 11])
def test_replacement_targets_cstring_values_only(type_code: int):
    payloads = {
        3: cstring(b'old'),
        9: b'old'.ljust(32, b'\0'),
        11: struct.pack('>i', 1) + cstring(b'old'),
    }
    content = document(tag('_PATIENT_ID', type_code, payloads[type_code]))

    assert replace_strings(content, {'_PATIENT_ID': 'new'}) == content


@pytest.mark.parametrize('type_code', [3, 10, 11, 12, 13])
def test_empty_variable_length_values_preserve_alignment(type_code: int):
    content = document(tag('empty', type_code, bytes(4)), tag('_PATIENT_ID', 10, cstring(b'old')))
    expected = document(tag('empty', type_code, bytes(4)), tag('_PATIENT_ID', 10, cstring(b'new')))
    assert replace_strings(content, {'_PATIENT_ID': 'new'}) == expected


@pytest.mark.parametrize(('type_code', 'payload'), WIRE_VALUES)
def test_truncated_typed_records_are_rejected(type_code: int, payload: bytes):
    content = document(tag('value', type_code, payload))
    # Every proper prefix is incomplete, including cuts inside the end label.
    for size in range(len(content)):
        with pytest.raises(CPersistFormatError):
            replace_strings(content[:size], {})


@pytest.mark.parametrize('content', [
    b'not a CPersist object',
    b'WS1_' + struct.pack('>i', -1),  # Negative label size
    b'WS1_' + struct.pack('>i', 2147483647),  # Impossible label size
    document(tag('value', 99, b'')),  # Unknown type: cannot determine width safely
    document(tag('nested', 2, tag('value', 5, bytes(4)))),  # Missing nested WS1_
    document(tag('nested', 2, b'WS1_')),  # Missing outer end after nested end
])
def test_malformed_structure_is_rejected(content: bytes):
    with pytest.raises(CPersistFormatError):
        replace_strings(content, {})


@pytest.mark.parametrize('type_code', [3, 10, 11, 12, 13])
def test_negative_lengths_and_list_counts_are_rejected(type_code: int):
    content = document(tag('value', type_code, struct.pack('>i', -1)))
    with pytest.raises(CPersistFormatError):
        replace_strings(content, {})


def test_replace_strings_validates_replacements_before_parsing():
    with pytest.raises(ValueError, match="must be Latin-1 for 'unused'"):
        replace_strings(b'not a CPersist object', {'unused': '\N{SNOWMAN}'})
