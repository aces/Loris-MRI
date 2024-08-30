"""This class performs database queries for point_3d table"""

from lib.point_3d import Point3D

__license__ = "GPLv3"


class Point3DDB:
    def __init__(self, db, verbose):
        """
        Constructor method for the PhysiologicalCoordSystem class.
        :param db                 : Database class object
         :type db                 : object
        :param verbose            : whether to be verbose
         :type verbose            : bool
        """

        self.db = db
        self.verbose = verbose

    def grep_point_by_coordinates(self, x: float, y: float, z: float):
        """
        Grep a point in db by coordinate if it exists
        :param x  : x coordinate
         :type x  : float
        :param y  : y coordinate
         :type y  : float
        :param z  : z coordinate
         :type z  : float
        :return: a point or None if it does not exist
         :rtype: Point3D | None
        """
        cp = self.db.pselect(
            query = "SELECT DISTINCT Point3DID "
                    "FROM point_3d "
                    "WHERE X = %s"
                    " AND Y = %s"
                    " AND Z = %s",
            args=(x, y, z,)
        )
        return Point3D(cp[0]['Point3DID'], x, y, z) if cp else None

    def grep_point_by_id(self, point_id: int):
        """
        Get a point 3d if it exists in db.
        :param point_id  : a point ID
         :type point_id  : int
        :return: a point or None if it does not exist
         :rtype: Point3D | None
        """
        cp = self.db.pselect(
            query = "SELECT X, Y, Z "
                    "FROM point_3d "
                    "WHERE Point3DID = %s",
            args=(point_id,)
        )
        return Point3D(point_id, cp[0]['X'], cp[0]['Y'], cp[0]['Z']) if cp else None

    def insert_point(self, p: Point3D):
        """
        Wrapper for insert_point_by_coordinates.
        :param p  : Point3D object
         :type p  : Point3D
        :return   : the id of the inserted point
         :rtype   : int
        :return: a point
         :rtype: Point3D
        """
        return self.insert_point_by_coordinates(p.x, p.y, p.z)

    def insert_point_by_coordinates(self, x: float, y: float, z: float):
        """
        Insert a point in db by coordinates.
        :param x  : x coordinate
         :type x  : float
        :param y  : y coordinate
         :type y  : float
        :param z  : z coordinate
         :type z  : float
        :return: a point
         :rtype: Point3D
        """
        pid = self.db.insert(
            table_name = 'point_3d',
            column_names = ('X', 'Y', 'Z'),
            values = (x, y, z),
            get_last_id = True
        )
        return Point3D(pid, x, y, z)

    def grep_or_insert_point(self, point: Point3D):
        """
        Wrapper around grep_or_insert_point_by_coordinates.
        Insert a point in db if it does not already exist.
        :param x  : x coordinate
         :type x  : float
        :param y  : y coordinate
         :type y  : float
        :param z  : z coordinate
         :type z  : float
        :return: a point
         :rtype: Point3D
        """
        return self.grep_or_insert_point_by_coordinates(point.x, point.y, point.z)

    def grep_or_insert_point_by_coordinates(self, x: float, y: float, z: float):
        """
        Insert a point in db by coordinates if it does not already exist.
        :param x  : x coordinate
         :type x  : float
        :param y  : y coordinate
         :type y  : float
        :param z  : z coordinate
         :type z  : float
        :return: a point
         :rtype: Point3D
        """
        p = self.grep_point_by_coordinates(x, y, z)
        if p is None:
            p = self.insert_point_by_coordinates(x, y, z)
        return p
