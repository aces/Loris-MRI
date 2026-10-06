from pathlib import Path

from loris_utils.parse import try_parse_float, try_parse_int

from loris_bids_utils.tsv import BidsTsvFile, BidsTsvRow


class BidsEegElectrodeTsvRow(BidsTsvRow):
    """
    Class representing a BIDS EEG or iEEG `electrodes.tsv` row.

    Documentation:
    - https://bids-specification.readthedocs.io/en/stable/modality-specific-files/electroencephalography.html#electrode-locations-electrodestsv
    - https://bids-specification.readthedocs.io/en/stable/modality-specific-files/intracranial-electroencephalography.html#electrode-description-electrodestsv
    """

    name: str
    x: float | None
    y: float | None
    z: float | None
    type: str | None
    material: str | None
    impedance: int | None

    def __init__(self, data: dict[str, str | None]):
        super().__init__(data)

        name = data.get('name')
        if name is None:
            raise Exception("Missing electrode name in BIDS electrode file.")

        self.name = name
        self.x = _try_parse_bids_float(data.get('x'))
        self.y = _try_parse_bids_float(data.get('y'))
        self.z = _try_parse_bids_float(data.get('z'))
        self.type = _nullify_bids_missing_value(data.get('type'))
        self.material = _nullify_bids_missing_value(data.get('material'))

        impedance = _nullify_bids_missing_value(data.get('impedance'))
        self.impedance = try_parse_int(impedance) if impedance is not None else None


class BidsEegElectrodesTsvFile(BidsTsvFile[BidsEegElectrodeTsvRow]):
    """
    Class representing a BIDS EEG or iEEG `electrodes.tsv` file.
    """

    def __init__(self, path: Path):
        super().__init__(BidsEegElectrodeTsvRow, path)


def _try_parse_bids_float(value: str | None) -> float | None:
    value = _nullify_bids_missing_value(value)
    return try_parse_float(value) if value is not None else None


def _nullify_bids_missing_value(value: str | None) -> str | None:
    if value is None or value.strip().lower() == 'n/a':
        return None
    return value
