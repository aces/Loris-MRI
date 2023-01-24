"""This class performs database queries for several coordinate system tables:
- physiological_coord_system,
- physiological_coord_system_name,
- physiological_coord_system_type,
- physiological_coord_system_unit,
- physiological_modality
- physiological_coord_system_electrode_rel,
- physiological_coord_system_point_3d_rel
"""

from typing import List
from lib.point_3d import Point3D
from lib.database_lib.point_3d import Point3DDB

__license__ = "GPLv3"

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
        :param coord_unit       : coord system unit name of the coord file (e.g. 'mm')
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

    def grep_coord_system_modality_from_name(self, coord_modality: str):
        """
        Gets the coord system type ID given a str name.
        :param coord_modality   : coord system modality name of the coord file
         :type coord_modality   : str
        :return                 : id of the coord system modality
         :rtype                 : int
        """
        c_mod = self.db.pselect(
            query = "SELECT DISTINCT PhysiologicalModalityID "
                    "FROM physiological_modality "
                    "WHERE PhysiologicalModality = %s",
            args=(coord_modality,)
        )
        return c_mod[0]['PhysiologicalModalityID'] if c_mod else None

    def insert_coord_system(self, coord_name: str, coord_unit: str, coord_type: str,
                            coord_mod: str, coord_file: str):
        """
        Inserts a new entry in the physiological_coord_system table.
        :param coord_name  : coord system name of the coord file
         :type coord_name  : str
        :param coord_unit  : unit name of the coord file
         :type coord_unit  : str
        :param coord_type  : type name of the coord file
         :type coord_type  : str
        :param coord_mod   : modality name of the coord file
         :type coord_mod   : str
        :param coord_file  : path of the coord system file
         :type coord_file  : str
        :return            : id of the row inserted
         :rtype            : int
        """

        c_name = self.grep_coord_system_name_from_name(coord_name)
        c_unit = self.grep_coord_system_unit_from_symbol(coord_unit)
        c_type = self.grep_coord_system_type_from_name(coord_type)
        c_mod  = self.grep_coord_system_modality_from_name(coord_mod)

        return self.db.insert(
            table_name = 'physiological_coord_system',
            column_names = (
                'Name',
                'Unit',
                'Type',
                'Modality'
                'FilePath'
            ),
            values = (
                c_name,
		c_unit,
		c_type,
		c_mod,
		coord_file
            ),
            get_last_id = True
        )

    def insert_coord_system_electrodes_relation(self, physiological_file_id: int,
						coord_system_id: int,
			                        electrode_ids: List[int]):
        """
        Inserts new entries in the physiological_coord_system_electrode_rel table.
        :param physiological_file_id : physiological file ID
         :type physiological_file_id : int
        :param coord_system_id       : coordinate system ID
         :type coord_system_id       : int
        :param electrode_ids         : list of electrode id associated with the coordinate system ID
         :type electrode_ids         : List[int]
        """
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

    def insert_coord_system_point_3d_relation(self, coord_system_id: int,
                                              point_ids: List[int]):
        """
        Insert new entries in the physiological_coord_system_point_3d_rel table.
        :param coord_system_id : coordinate system ID
         :type coord_system_id : int
        :param point_ids       : list of point_3d id associated with the coordinate system ID
         :type point_ids       : List[int]
        """
        values_to_insert = [
            (coord_system_id, pid)
            for pid in point_ids
        ]
        self.db.insert(
            table_name = 'physiological_coord_system_point_3d_rel',
            column_names = (
                'PhysiologicalCoordSystemID',
                'Point3DID '
            ),
            values = values_to_insert
        )

    def grep_coord_system_points(self, coord_system_id: int) -> List[int]:
        """
        Get all points_3d IDs associated with a cooordinate system.
        This method get the coordinate system reference points, not the actual electrode points.
        """
        c_points = self.db.pselect(
            query = "SELECT DISTINCT Point3DID "
                    "FROM physiological_coord_system_point_3d_rel "
                    "WHERE PhysiologicalCoordSystemID = %s",
            args=(coord_system_id,)
        )
        return [c['Point3DID'] for c in c_points] if c_points else []

