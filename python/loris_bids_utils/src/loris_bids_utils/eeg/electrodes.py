from pathlib import Path

from loris_utils.iter import map_non_none
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
        self.x = map_non_none(data.get('x'), try_parse_float)
        self.y = map_non_none(data.get('y'), try_parse_float)
        self.z = map_non_none(data.get('z'), try_parse_float)
        self.type = data.get('type')
        self.material = data.get('material')

        self.impedance = map_non_none(data.get('impedance'), try_parse_int)


class BidsEegElectrodesTsvFile(BidsTsvFile[BidsEegElectrodeTsvRow]):
    """
    Class representing a BIDS EEG or iEEG `electrodes.tsv` file.
    """

    def __init__(self, path: Path):
        super().__init__(BidsEegElectrodeTsvRow, path)
