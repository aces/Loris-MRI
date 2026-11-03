from dataclasses import dataclass
from pathlib import Path

import numpy as np

VecF = np.ndarray[tuple[int], np.dtype[np.float64]]


@dataclass
class MegCtfHeadShapePoint:
    """
    A point in a MEG CTF `headshape.pos` file.
    """

    label: str
    """
    The point name or index. A given name may occur more than once in a head shape file.
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
            label = self.label,
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

    points: list[MegCtfHeadShapePoint]
    """
    The points in file order.
    """

    @staticmethod
    def read(path: Path) -> 'MegCtfHeadShapeFile':
        """
        Read and parse a MEG CTF head shape file.
        """

        with path.open() as file:
            lines = file.readlines()

        points: list[MegCtfHeadShapePoint] = []
        # The first line simply gives the number of points.
        for line in lines[1:]:
            parts = line.split()
            # The first column contains the sensor name or index.
            # The second column may or may not be empty.
            # The last three columns contain the point coordinates.
            points.append(MegCtfHeadShapePoint(
                label = parts[0],
                x = float(parts[-3]),
                y = float(parts[-2]),
                z = float(parts[-1]),
            ))

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
            points = [point.scale(factor) for point in self.points],
        )

    def get_landmark(self, landmark_labels: list[str]) -> MegCtfHeadShapePoint | None:
        """
        Get a landmark point using the provided landmark labels.

        Label comparison is case-insensitive, whenever several points exist for this landmark, the
        average coordinates of these points are used. The result uses the first requested label.
        """

        caseless_labels = {name.casefold() for name in landmark_labels}

        lamdmark_points = [
            point
            for point in self.points
            if point.label.casefold() in caseless_labels
        ]

        if lamdmark_points == []:
            return None

        return MegCtfHeadShapePoint(
            label = landmark_labels[0],
            x = sum(point.x for point in lamdmark_points) / len(lamdmark_points),
            y = sum(point.y for point in lamdmark_points) / len(lamdmark_points),
            z = sum(point.z for point in lamdmark_points) / len(lamdmark_points),
        )

    @property
    def nasion(self) -> MegCtfHeadShapePoint | None:
        """
        Get the mean nasion fiducial position across NAS and Nasion labels, ignoring case.
        """

        return self.get_landmark(['NAS', 'Nasion'])

    @property
    def lpa(self) -> MegCtfHeadShapePoint | None:
        """
        Get the mean LPA fiducial position across LPA and left labels, ignoring case.
        """

        return self.get_landmark(['LPA', 'left'])

    @property
    def rpa(self) -> MegCtfHeadShapePoint | None:
        """
        Get the mean RPA fiducial position across RPA and right labels, ignoring case.
        """

        return self.get_landmark(['RPA', 'right'])
