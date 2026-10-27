from pathlib import Path

import pytest

from loris_bids_utils.meg.ctf.head_shape import MegCtfHeadShapeFile, MegCtfHeadShapePoint


@pytest.fixture
def head_shape(tmp_path: Path) -> MegCtfHeadShapeFile:
    path = tmp_path / 'headshape.pos'
    path.write_text(
        '2\n'
        '1\tCz\t1.0\t2.0\t3.0\n'
        '2\t\t4.0\t5.0\t6.0\n'
        'Nasion\t7.0\t8.0\t9.0\n'
        'LPA\t10.0\t11.0\t12.0\n'
        'RPA\t13.0\t14.0\t15.0\n'
        'Nasion\t16.0\t17.0\t18.0\n'
        'LPA\t19.0\t20.0\t21.0\n'
        'RPA\t22.0\t23.0\t24.0\n'
        'HPI-N\t25.0\t26.0\t27.0\n'
        'HPI-N\t28.0\t29.0\t30.0\n'
    )
    return MegCtfHeadShapeFile.read(path)


def test_read_preserves_repeated_labels_and_file_order(head_shape: MegCtfHeadShapeFile):
    assert head_shape.points == [
        MegCtfHeadShapePoint('1', 1, 2, 3),
        MegCtfHeadShapePoint('2', 4, 5, 6),
        MegCtfHeadShapePoint('Nasion', 7, 8, 9),
        MegCtfHeadShapePoint('LPA', 10, 11, 12),
        MegCtfHeadShapePoint('RPA', 13, 14, 15),
        MegCtfHeadShapePoint('Nasion', 16, 17, 18),
        MegCtfHeadShapePoint('LPA', 19, 20, 21),
        MegCtfHeadShapePoint('RPA', 22, 23, 24),
        MegCtfHeadShapePoint('HPI-N', 25, 26, 27),
        MegCtfHeadShapePoint('HPI-N', 28, 29, 30),
    ]


def test_scale_preserves_repeated_labels(head_shape: MegCtfHeadShapeFile):
    scaled = head_shape.scale(10)

    assert scaled.path == head_shape.path
    assert len(scaled.points) == 10
    assert scaled.points[2] == MegCtfHeadShapePoint('Nasion', 70, 80, 90)
    assert scaled.points[5] == MegCtfHeadShapePoint('Nasion', 160, 170, 180)
    assert scaled.points[-1] == MegCtfHeadShapePoint('HPI-N', 280, 290, 300)
    assert head_shape.points[2] == MegCtfHeadShapePoint('Nasion', 7, 8, 9)


def test_landmarks_average_repeated_measurements(head_shape: MegCtfHeadShapeFile):
    original_points = head_shape.points.copy()

    assert head_shape.nasion == MegCtfHeadShapePoint('NAS', 11.5, 12.5, 13.5)
    assert head_shape.lpa == MegCtfHeadShapePoint('LPA', 14.5, 15.5, 16.5)
    assert head_shape.rpa == MegCtfHeadShapePoint('RPA', 17.5, 18.5, 19.5)
    assert head_shape.points == original_points


@pytest.mark.parametrize('label,attribute,canonical_label', [
    ('NAS', 'nasion', 'NAS'),
    ('Nasion', 'nasion', 'NAS'),
    ('nAsIoN', 'nasion', 'NAS'),
    ('LPA', 'lpa', 'LPA'),
    ('LEFT', 'lpa', 'LPA'),
    ('RPA', 'rpa', 'RPA'),
    ('Right', 'rpa', 'RPA'),
])
def test_landmark_aliases(label: str, attribute: str, canonical_label: str):
    point = MegCtfHeadShapePoint(label, 1, 2, 3)
    head_shape = MegCtfHeadShapeFile(Path('headshape.pos'), [point])

    assert getattr(head_shape, attribute) == MegCtfHeadShapePoint(canonical_label, 1, 2, 3)


def test_landmarks_average_all_aliases_case_insensitively():
    head_shape = MegCtfHeadShapeFile(Path('headshape.pos'), [
        MegCtfHeadShapePoint('NAS', 1, 2, 3),
        MegCtfHeadShapePoint('Nasion', 4, 5, 6),
        MegCtfHeadShapePoint('nAsIoN', 7, 8, 9),
        MegCtfHeadShapePoint('LPA', 1, 2, 3),
        MegCtfHeadShapePoint('LEFT', 4, 5, 6),
        MegCtfHeadShapePoint('RPA', 1, 2, 3),
        MegCtfHeadShapePoint('Right', 4, 5, 6),
        MegCtfHeadShapePoint('HPI-N', 100, 200, 300),
        MegCtfHeadShapePoint('HPI-L', 100, 200, 300),
        MegCtfHeadShapePoint('HPI-R', 100, 200, 300),
    ])

    assert head_shape.nasion == MegCtfHeadShapePoint('NAS', 4, 5, 6)
    assert head_shape.lpa == MegCtfHeadShapePoint('LPA', 2.5, 3.5, 4.5)
    assert head_shape.rpa == MegCtfHeadShapePoint('RPA', 2.5, 3.5, 4.5)

    head_shape.points.reverse()
    assert head_shape.nasion == MegCtfHeadShapePoint('NAS', 4, 5, 6)


def test_get_landmark_does_not_count_aliases_twice(head_shape: MegCtfHeadShapeFile):
    assert head_shape.get_landmark(['NAS', 'Nasion', 'nasion']) == MegCtfHeadShapePoint('NAS', 11.5, 12.5, 13.5)
    assert head_shape.get_landmark([]) is None
    assert head_shape.get_landmark(['unknown']) is None


def test_missing_landmarks():
    head_shape = MegCtfHeadShapeFile(Path('headshape.pos'), [])

    assert head_shape.nasion is None
    assert head_shape.lpa is None
    assert head_shape.rpa is None
