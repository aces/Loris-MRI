"""This class represents a Point with 3D coordinates"""


class Point3D:
    def __init__(self, pid: int, x: float, y: float, z: float):
        """
        Create a new point 3D object
        :param pid  : point ID, can be None
         :type pid  : int
        :param x  : x coordinate
         :type x  : float
        :param y  : y coordinate
         :type y  : float
        :param z  : z coordinate
         :type z  : float
        """
        self.id = pid
        self.x = x
        self.y = y
        self.z = z

    def __str__(self) -> str:
        """Prints out the point info"""
        return f"Point [{self.id}] ({self.x}, {self.y}, {self.z})"
