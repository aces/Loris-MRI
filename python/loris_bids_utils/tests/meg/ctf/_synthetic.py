"""Synthetic CTF records; no production serializers or format constants.

The code has been generated from the following code and documentation:
- **MEG sample encoding, RES4 header and field sizes** —
  https://megcore.nih.gov/images/a/a8/FileFormats.pdf
  (CTF MEG File Formats, PN900-0088 revision 1.3), printed pp. 11, 13, 30-32
- **RES4 field read order and alignment** —
  https://github.com/brainstorm-tools/brainstorm3/blob/master/toolbox/io/ctf_read_res4.m
  (Brainstorm `ctf_read_res4.m`), header reading section
- **Split signal filenames and nested head localization datasets** —
  https://github.com/brainstorm-tools/brainstorm3/blob/master/toolbox/io/ctf_get_files.m
  (Brainstorm `ctf_get_files.m`); PN900-0088 p. 51
- **Patient information tags, marker/class records** —
  PN900-0088 Table 6 and pp. 57-64
- **CPersist numeric types, nesting, byte order and lengths** —
  PN900-0088 Appendix B, pp. 153-155
- **Length-prefixed end labels and CString storage details** —
  https://github.com/Moo-Marc/CtfMegBids/blob/f550ecf776733f92d0855e294309b2a1e93a262d/BstDependencies/readCPersist.m
  (CTF `readCPersist.m` distributed with CtfMegBids)
"""

import struct


def tag(label: str, type_code: int, payload: bytes) -> bytes:
    """PN900-0088 Appendix B: label length, label, numeric type, payload."""
    name = label.encode('ascii')
    return struct.pack('>i', len(name)) + name + struct.pack('>i', type_code) + payload


def cstring(value: bytes) -> bytes:
    """Length-prefixed bytes, as consumed by CTF readCPersist.m type 10."""
    return struct.pack('>i', len(value)) + value


def document(*tags: bytes) -> bytes:
    """The end label has a length prefix but no type or value."""
    return b'WS1_' + b''.join(tags) + b'\x00\x00\x00\x0fEndOfParameters'


def resource_file(subject: bytes) -> bytes:
    """Assemble fields in Brainstorm ctf_read_res4.m read order.

    Include the general resources, zero filters/channels/coefficients, and an
    opaque tail to detect unintended writes. This is not a playable acquisition.
    """
    return b''.join([
        b'MEG42RS\0',
        b'acquisition app'.ljust(256, b'\0'),
        b'origin'.ljust(256, b'\0'),
        b'description'.ljust(256, b'\0'),
        struct.pack('>h', 1),
        b'09:43:00'.ljust(255, b'\0'),
        b'01-Jan-1925'.ljust(255, b'\0'),
        # gSetUp, including explicit alignment and its final padding word.
        struct.pack('>ih2xddh2xihhi10shih2xiii',
                    4, 0, 2400.0, 4 / 2400, 1, 0, 1, 1, 1,
                    bytes(10), 0, 0, 0, 0, 0, 0),
        b'run'.ljust(32, b'\0'),
        b'run title'.ljust(256, b'\0'),
        b'instrument'.ljust(32, b'\0'),
        b'collection'.ljust(32, b'\0'),
        subject.ljust(32, b'\0'),
        b'operator'.ljust(32, b'\0'),
        b'sensor file'.ljust(60, b'\0'),
        struct.pack('>i', 0),  # Run description length
        bytes(4),  # Unused word at 1840
        struct.pack('>hh', 0, 0),  # No filters or coefficient records
        bytes(range(256)),
    ])


def patient_info(subject: bytes) -> bytes:
    """PN900-0088 Table 6: nested patient and dataset information groups."""
    return document(
        tag('_PATIENT_INFO', 2, document(
            tag('_PATIENT_ID', 10, cstring(subject)),
            tag('_PATIENT_NAME_LAST', 10, cstring(b'Example\0')),
            tag('_PATIENT_SEX', 5, struct.pack('>i', 2)),
        )),
        tag('_DATASET_INFO', 2, document(
            tag('_DATASET_COLLECTIONDATETIME', 10, cstring(b'19250101094300')),
            tag('_DATASET_COMMENTS', 10, cstring(subject)),
            tag('_DATASET_MAXHEADMOTION', 4, struct.pack('>d', 0.001)),
        )),
    )
