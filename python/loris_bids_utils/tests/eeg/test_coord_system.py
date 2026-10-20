import json
from pathlib import Path

from loris_bids_utils.eeg.coord_system import BidsCoordSystemJsonFile


def test_parse_bids_coord_systems_keeps_every_description(tmp_path: Path):
    path = tmp_path / 'coordsystem.json'
    path.write_text(json.dumps({
        'HeadCoilCoordinateSystem': 'CTF',
        'HeadCoilCoordinateUnits': 'cm',
        'HeadCoilCoordinates': {'coil1': [1, 2, 3]},
        'MEGCoordinateSystem': 'CTF',
        'MEGCoordinateUnits': 'm',
        'EEGCoordinateSystem': 'CapTrak',
        'EEGCoordinateUnits': 'mm',
        'AnatomicalLandmarkCoordinateSystem': 'CTF',
        'AnatomicalLandmarkCoordinateUnits': 'mm',
        'AnatomicalLandmarkCoordinates': {'NAS': [4, 5, 6]},
    }))
    definitions = BidsCoordSystemJsonFile(path).get_coord_systems()

    assert [item.kind for item in definitions] == [
        'MEG',
        'EEG',
        'HeadCoil',
        'AnatomicalLandmark',
    ]
    assert definitions[2].points == {'coil1': (1.0, 2.0, 3.0)}


def test_parse_bids_coord_systems_adds_missing_sensor_system(tmp_path: Path):
    path = tmp_path / 'coordsystem.json'
    path.write_text(json.dumps({
        'FiducialsCoordinateSystem': 'CTF',
        'FiducialsCoordinateUnits': 'mm',
    }))
    definitions = BidsCoordSystemJsonFile(path).get_coord_systems()

    assert len(definitions) == 1
    assert definitions[0].kind == 'Fiducials'
