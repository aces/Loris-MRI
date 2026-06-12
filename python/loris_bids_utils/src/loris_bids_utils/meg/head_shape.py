from dataclasses import dataclass
from pathlib import Path

import numpy as np

VecF = np.ndarray[tuple[int], np.dtype[np.float64]]


@dataclass
class MegCtfHeadShapePoint:
    """
    A point in a MEG CTF `headshape.pos` file.
    """

    x: float
    y: float
    z: float

    def scale(self, factor: float) -> 'MegCtfHeadShapePoint':
        """
        Scale the point coordinates by a factor. Notably useful to convert the head shape point from
        one unit to another.
        """

        return MegCtfHeadShapePoint(
            x = self.x * factor,
            y = self.y * factor,
            z = self.z * factor,
        )

    def to_numpy(self) -> VecF:
        """
        Convert the point to a numpy array.
        """

        return np.array([self.x, self.y, self.z], dtype=np.float64)


@dataclass
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

    @staticmethod
    def read(path: Path) -> 'MegCtfHeadShapeFile':
        """
        Read and parse a MEG CTF head shape file.
        """

        with path.open() as file:
            lines = file.readlines()

        points: dict[str, MegCtfHeadShapePoint] = {}
        # The first line simply gives the number of points.
        for line in lines[1:]:
            parts = line.split()
            # The first column contains the sensor name or index.
            # The second column may or may not be empty.
            # The last three columns contain the point coordimates.
            points[parts[0]] = MegCtfHeadShapePoint(float(parts[-3]), float(parts[-2]), float(parts[-1]))

        return MegCtfHeadShapeFile(
            path   = path,
            points = points,
        )

    def scale(self, factor: float) -> 'MegCtfHeadShapeFile':
        """
        Create a new head shape file with all points scaled by a factor.
        """

        return MegCtfHeadShapeFile(
            path = self.path,
            points = {name: point.scale(factor) for name, point in self.points.items()},
        )

    @property
    def nasion(self) -> MegCtfHeadShapePoint | None:
        """
        Get the nasion fiducial point.
        """

        return self.points.get('NAS') or self.points.get('Nasion')

    @property
    def lpa(self) -> MegCtfHeadShapePoint | None:
        """
        Get the LPA fiducial point.
        """

        return self.points.get('LPA')

    @property
    def rpa(self) -> MegCtfHeadShapePoint | None:
        """
        Get the RPA fiducial point.
        """

        return self.points.get('RPA')
