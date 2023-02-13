"""This class performs database queries for several coordinate system tables:
- physiological_coord_system,
- physiological_coord_system_name,
- physiological_coord_system_type,
- physiological_coord_system_unit,
- physiological_modality
- physiological_coord_system_electrode_rel,
- physiological_coord_system_point_3d_rel
"""

from typing import Dict, List
# from lib.point_3d import Point3D
# from lib.database_lib.point_3d import Point3DDB

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
            query="SELECT DISTINCT PhysiologicalCoordSystemNameID "
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
            query="SELECT DISTINCT PhysiologicalCoordSystemUnitID "
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
            query="SELECT DISTINCT PhysiologicalCoordSystemTypeID "
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
            query="SELECT DISTINCT PhysiologicalModalityID "
            "FROM physiological_modality "
            "WHERE PhysiologicalModality = %s",
            args=(coord_modality,)
        )
        return c_mod[0]['PhysiologicalModalityID'] if c_mod else None

    def grep_coord_system(self, coord_mod_id: int, coord_name_id: int = None,
                          coord_unit_id: int = None, coord_type_id: int = None):
        """
        Get a coordinate system by ID.
        Requires at least the modality.
        :param name_id     : coord system name id
         :type name_id     : int
        :param unit_id     : unit id
         :type unit_id     : int
        :param type_id     : type id
         :type type_id     : int
        :param mod_id      : modality id
         :type mod_id      : int
        :param coord_file  : path of the coord system file
         :type coord_file  : str
        :return            : The coordinate system ID or None
         :rtype            : int | None
        """
        q_args = (coord_mod_id,)
        q_extra = "SELECT DISTINCT PhysiologicalCoordSystemID " \
                  "FROM physiological_coord_system " \
                  "WHERE ModalityID = %s"
        # add name id
        if coord_name_id is not None:
            q_args += (coord_name_id,)
            q_extra += " AND NameID = %s"
        # add type id
        if coord_type_id is not None:
            q_args += (coord_type_id,)
            q_extra += " AND TypeID = %s"
        # add unit id
        if coord_unit_id is not None:
            q_args += (coord_unit_id,)
            q_extra += " AND UnitID = %s"
        # execute query
        r_query = self.db.pselect(
            query = q_extra,
            args = q_args
        )
        return r_query[0]['PhysiologicalCoordSystemID'] if r_query else None

    def insert_coord_system(self, name_id: int, unit_id: int, type_id: int,
                            mod_id: int, coord_file: str):
        """
        Inserts a new entry in the physiological_coord_system table.
        :param name_id     : coord system name id
         :type name_id     : int
        :param unit_id     : unit id
         :type unit_id     : int
        :param type_id     : type id
         :type type_id     : int
        :param mod_id      : modality id
         :type mod_id      : int
        :param coord_file  : path of the coord system file
         :type coord_file  : str
        :return            : The inserted coordinate system ID or None
         :rtype            : int
        """
        return self.db.insert(
            table_name='physiological_coord_system',
            column_names=(
                'NameID',
                'UnitID',
                'TypeID',
                'ModalityID',
                'FilePath'
            ),
            values=(
                name_id,
                unit_id,
                type_id,
                mod_id,
                coord_file
            ),
            get_last_id=True
        )

    def grep_or_insert_coord_system(self, name_id: int, unit_id: int, type_id: int,
                                    mod_id: int, coord_file: str):
        """
        Inserts a new entry in the physiological_coord_system table if it does not exist.
        :param name_id     : coord system name id
         :type name_id     : int
        :param unit_id     : unit id
         :type unit_id     : int
        :param type_id     : type id
         :type type_id     : int
        :param mod_id      : modality id
         :type mod_id      : int
        :param coord_file  : path of the coord system file
         :type coord_file  : str
        :return            : The coordinate system ID or None
         :rtype            : int
        """
        coord_system_id = self.grep_coord_system(mod_id, name_id, unit_id, type_id)
        if coord_system_id is None:
            coord_system_id = self.insert_coord_system(name_id, unit_id, type_id, mod_id, coord_file)
        return coord_system_id

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
            table_name='physiological_coord_system_electrode_rel',
            column_names=(
                'PhysiologicalCoordSystemID',
                'PhysiologicalElectrodeID',
                'PhysiologicalFileID '
            ),
            values=values_to_insert
        )

    def insert_coord_system_point_3d_relation(self, coord_system_id: int,
                                              point_ids: Dict[str, int]):
        """
        Insert new entries in the physiological_coord_system_point_3d_rel table.
        :param coord_system_id : coordinate system ID
         :type coord_system_id : int
        :param point_ids       : dict of (point name,point_3d id) associated with the coordinate system ID
         :type point_ids       : Dict[str, int]
        """
        values_to_insert = []
        for name, pid in point_ids.items():
            r = self.db.pselect(
                query="SELECT * "
                "FROM physiological_coord_system_point_3d_rel "
                "WHERE PhysiologicalCoordSystemID = %s "
                "AND Point3DID = %s ",
                args=(coord_system_id, pid,)
            )
            if not r:
                values_to_insert.append((coord_system_id, pid, name))
        self.db.insert(
            table_name='physiological_coord_system_point_3d_rel',
            column_names=(
                'PhysiologicalCoordSystemID',
                'Point3DID',
                'Name'
            ),
            values=values_to_insert
        )