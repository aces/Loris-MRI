from dataclasses import dataclass
from decimal import Decimal
from pathlib import Path


@dataclass
class MegCtfHeadShapePoint:
    """
    A point in a MEG CTF `headshape.pos` file.
    """

    x: Decimal
    y: Decimal
    z: Decimal


class MegCtfHeadShapeFile:
    """
    A MEG CTF `headshape.pos` file.
    """

    path: Path
    """
    The path of this head shape file.
    """

    points: dict[str, MegCtfHeadShapePoint]
    """
    The points of this head shape file.
    """

    def __init__(self, path: Path):
        with path.open() as file:
            lines = file.readlines()

        points: dict[str, MegCtfHeadShapePoint] = {}
        for line in lines[1:]:
            parts = line.split()
            points[parts[0]] = MegCtfHeadShapePoint(Decimal(parts[1]), Decimal(parts[2]), Decimal(parts[3]))

        self.path   = path
        self.points = points
