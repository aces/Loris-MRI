"""This class performs database queries for several coordinate system tables:
- physiological_coord_system,
- physiological_coord_system_name,
- physiological_coord_system_type,
- physiological_coord_system_unit,
- and physiological_coord_system_electrode_rel,
"""

from collections import namedtuple

__license__ = "GPLv3"

# coordinate triplet (x, y, z)
Coord3d = namedtuple("Coord", "x y z")


class PhysiologicalCoordSystem:

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

    def grep_coord_system_name_from_name(self, coord_name: str):
        """
        Gets the coord system name ID given a str name.

        :param coord_name       : coord system name of the coord file
         :type coord_name       : str

        :return                 : id of the coord system name
         :rtype                 : int
        """
        c_name = self.db.pselect(
            query = "SELECT DISTINCT PhysiologicalCoordSystemNameID "
                    "FROM physiological_coord_system_name "
                    "WHERE Name = %s",
            args=(coord_name,)
        )
        return c_name[0]['PhysiologicalCoordSystemNameID'] if c_name else None

    def grep_coord_system_unit_from_symbol(self, coord_unit: str):
        """
        Gets the coord system unit ID given a str name.

        :param coord_unit       : coord system unit name of the coord file
         :type coord_unit       : str

        :return                 : id of the coord system unit
         :rtype                 : int
        """
        c_unit = self.db.pselect(
            query = "SELECT DISTINCT PhysiologicalCoordSystemUnitID "
                    "FROM physiological_coord_system_unit "
                    "WHERE Symbol = %s",
            args=(coord_unit,)
        )
        return c_unit[0]['PhysiologicalCoordSystemUnitID'] if c_unit else None

    def grep_coord_system_type_from_name(self, coord_type: str):
        """
        Gets the coord system type ID given a str name.

        :param coord_type       : coord system type name of the coord file
         :type coord_type       : str

        :return                 : id of the coord system type
         :rtype                 : int
        """
        c_type = self.db.pselect(
            query = "SELECT DISTINCT PhysiologicalCoordSystemTypeID "
                    "FROM physiological_coord_system_type "
                    "WHERE Name = %s",
            args=(coord_type,)
        )
        return c_type[0]['PhysiologicalCoordSystemTypeID'] if c_type else None

    def insert_coord_system(self, coord_name, coord_unit, coord_type,
                            coord_nas: Coord3d, coord_lpa: Coord3d,
                            coord_rpa: Coord3d, coord_file: str):
        """
        Inserts a new entry in the physiological_coord_system table.

        :param coord_name  : coord system name of the coord file
         :type coord_name  : str

        :param coord_name  : unit name of the coord file
         :type coord_name  : str

        :param coord_name  : type name of the coord file
         :type coord_name  : str

        :param coord_file  : path of the coord system file
         :type coord_file  : str

        :return            : id of the row inserted
         :rtype            : int
        """

        c_name = self.grep_coord_system_name_from_name(coord_name)
        c_unit = self.grep_coord_system_unit_from_symbol(coord_unit)
        c_type = self.grep_coord_system_type_from_name(coord_type)

        return self.db.insert(
            table_name = 'physiological_coord_system',
            column_names = (
                'CoordName', 'CoordUnit', 'CoordType',
                'CoordNASX', 'CoordNASY', 'CoordNASZ',
                'CoordLPAX', 'CoordLPAY', 'CoordLPAZ',
                'CoordRPAX', 'CoordRPAY', 'CoordRPAZ',
                'FilePath'
            ),
            values = (
                c_name, c_unit, c_type,
                coord_nas.x, coord_nas.y, coord_nas.z,
                coord_lpa.x, coord_lpa.y, coord_lpa.z,
                coord_rpa.x, coord_rpa.y, coord_rpa.z,
                coord_file
            ),
            get_last_id = True
        )

    def insert_relation(self, coord_system_id, electrode_ids, physiological_file_id):
        values_to_insert = [
            (coord_system_id, eid, physiological_file_id)
            for eid in electrode_ids
        ]
        self.db.insert(
            table_name = 'physiological_coord_system_electrode_rel',
            column_names = (
                'PhysiologicalCoordSystemID',
                'PhysiologicalElectrodeID',
                'PhysiologicalFileID '
            ),
            values = values_to_insert
        )
