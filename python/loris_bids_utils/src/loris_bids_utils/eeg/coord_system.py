from dataclasses import dataclass
from typing import Any, cast

from loris_bids_utils.json import BidsJsonFile

BIDS_COORD_SYSTEM_KINDS: list[str] = [
    'MEG',
    'EEG',
    'iEEG',
    'HeadCoil',
    'DigitizedHeadPoints',
    'AnatomicalLandmark',
    'Fiducials',
]


@dataclass(frozen=True)
class BidsCoordSystem:
    """
    A coordinate system description parsed from a BIDS `coordsystem.json` file.
    """

    kind: str
    name: str
    unit: str | None
    points: dict[str, tuple[float, float, float]]


class BidsCoordSystemJsonFile(BidsJsonFile):
    """
    Class representing a BIDS `coordsystem.json` file.
    """

    def get_coord_systems(self) -> list[BidsCoordSystem]:
        """
        Parse every coordinate system description in this file.
        """

        definitions: list[BidsCoordSystem] = []
        for kind in BIDS_COORD_SYSTEM_KINDS:
            system_key = f'{kind}CoordinateSystem'
            if system_key not in self.data:
                continue

            definitions.append(BidsCoordSystem(
                kind   = kind,
                name   = str(self.data[system_key]),
                unit   = _parse_unit(self.data.get(f'{kind}CoordinateUnits')),
                points = _parse_points(self.data.get(f'{kind}Coordinates')),
            ))

        return definitions


def _parse_unit(value: Any) -> str | None:
    return value if isinstance(value, str) and value != 'n/a' else None


def _parse_points(value: Any) -> dict[str, tuple[float, float, float]]:
    if not isinstance(value, dict):
        return {}

    points: dict[str, tuple[float, float, float]] = {}
    for name, untyped_coordinates in cast(dict[object, object], value).items():
        coordinates = cast(list[object], untyped_coordinates) if isinstance(untyped_coordinates, list) else None
        if (
            isinstance(name, str)
            and coordinates is not None
            and len(coordinates) == 3
            and all(isinstance(coordinate, int | float) for coordinate in coordinates)
        ):
            points[name] = (
                float(cast(int | float, coordinates[0])),
                float(cast(int | float, coordinates[1])),
                float(cast(int | float, coordinates[2])),
            )
    return points
