"""This class performs database queries for BIDS physiological dataset (EEG, MEG...)"""

from dataclasses import dataclass
from functools import reduce

from lib.database_lib.physiological_coord_system import PhysiologicalCoordSystem
from lib.database_lib.point_3d import Point3DDB
from lib.db.models.physio_file import DbPhysioFile
from lib.env import Env
from lib.physio.parameters import insert_physio_file_parameter
from lib.point_3d import Point3D


class Physiological:
    """
    This class performs database queries for BIDS physiological dataset (EEG,
    MEG...).

    :Example:

        from lib.physiological import Physiological
        from lib.database      import Database

        # database connection
        db = Database(config.mysql, verbose)
        db.connect()

        physiological = Physiological(env, db, verbose)

        # Get file type for the physiological file
        file_type = physiological.get_file_type(eeg_file)

        # grep a PhysiologicalFileID based on a blake2b hash
        file_id = physiological.grep_file_id_from_hash(blake2)

        # insert electrode file into physiological_electrode
        physiological.insert_electrode_file(
            electrode_data, electrode_path, physiological_file_id, blake2
        )

        ...
    """

    def __init__(self, env: Env, db, verbose):
        """
        Constructor method for the Physiological class.

        :param db     : Database class object
         :type db     : object
        :param verbose: whether to be verbose
         :type verbose: bool
        """

        self.env     = env
        self.db      = db
        self.verbose = verbose

        self.physiological_coord_system_db = PhysiologicalCoordSystem(self.db, self.verbose)
        self.point_3d_db = Point3DDB(self.db, self.verbose)

    def grep_electrode_from_physiological_file_id(self, physiological_file_id):
        """
        Greps all entries present in the physiological_electrode table for a
        given PhysiologicalFileID and returns its result.

        :param physiological_file_id: physiological file's ID
         :type physiological_file_id: int

        :return: tuple of dictionaries with one entry in the tuple
                 corresponding to one entry in physiological_electrode
         :rtype: tuple
        """

        results = self.db.pselect(
            query = "SELECT * "
                    "FROM physiological_electrode "
                    "WHERE PhysiologicalElectrodeID "
                    "IN ("
                    "    SELECT PhysiologicalElectrodeID "
                    "    FROM physiological_coord_system_electrode_rel "
                    "    WHERE PhysiologicalFileID = %s)",
            args  = (physiological_file_id,)
        )

        return results

    def insert_electrode_file(self, electrode_data, electrode_file,
                              physiological_file: DbPhysioFile, blake2):
        """
        Inserts the electrode information read from the file *electrode.tsv
        into the physiological_electrode table, linking it to the
        physiological file ID already inserted in physiological_file.

        :param electrode_data       : list with dictionaries of electrodes
                                      information to insert into
                                      physiological_electrode
         :type electrode_data       : list
        :param electrode_file       : name of the electrode file
         :type electrode_file       : str
        :param physiological_file   : Physiological file object to link the
                                      electrode information to
        :param blake2               : blake2b hash of the electrode file
         :type blake2               : str
        """

        # gather values that need to be inserted into physiological_electrode table
        electrode_fields = (
            'PhysiologicalElectrodeTypeID',
            'PhysiologicalElectrodeMaterialID',
            'Name',
            'Point3DID',
            'Impedance',
            'FilePath'
        )
        electrode_ids = []
        optional_fields = ('type', 'material', 'impedance')
        for row in electrode_data:
            for field in optional_fields:
                if field not in row.keys():
                    continue

                if field == 'type':
                    row['type_id'] = self.db.grep_id_from_lookup_table(
                        id_field_name       = 'PhysiologicalElectrodeTypeID',
                        table_name          = 'physiological_electrode_type',
                        where_field_name    = 'ElectrodeType',
                        where_value         = row['type'],
                        insert_if_not_found = True
                    )
                if field == 'material':
                    row['material_id'] = self.db.grep_id_from_lookup_table(
                        id_field_name       = 'PhysiologicalElectrodeMaterialID',
                        table_name          = 'physiological_electrode_material',
                        where_field_name    = 'ElectrodeMaterial',
                        where_value         = row['material'],
                        insert_if_not_found = True
                    )

            # map the X, Y and Z 'n/a' values to NULL
            x_value = None if row['x'] == 'n/a' else row['x']
            y_value = None if row['y'] == 'n/a' else row['y']
            z_value = None if row['z'] == 'n/a' else row['z']
            p = Point3D(None, x_value, y_value, z_value)
            point = self.point_3d_db.grep_or_insert_point(p)

            # insert into physiological_electrode table
            values_tuple = (
                row.get('type_id'),
                row.get('material_id'),
                row['name'],
                point.id,
                row.get('impedance'),
                electrode_file
            )

            inserted_electrode_id = self.db.insert(
                table_name   = 'physiological_electrode',
                column_names = electrode_fields,
                values       = values_tuple,
                get_last_id  = True
            )
            electrode_ids.append(inserted_electrode_id)

        # insert blake2b hash of electrode file into physiological_parameter_file
        insert_physio_file_parameter(self.env, physiological_file, 'electrode_file_blake2b_hash', blake2)
        return electrode_ids

    def insert_electrode_metadata(self, electrode_metadata, electrode_metadata_file,
                                  physiological_file: DbPhysioFile, blake2, electrode_ids):
        """
        Inserts the electrode metadata information read from the file *coordsystem.json
        into the physiological_coord_system, physiological_coord_system_point_3d_rel
        and physiological_coord_system_electrode_rel tables, linking it to the
        physiological file ID already inserted in physiological_file.
        :param electrode_metadata       : dictionaries of electrode metadata to insert
                                          into the database
         :type electrode_metadata       : dict
        :param electrode_metadata_file  : PhysiologicalFileID to link the electrode info to
         :type electrode_metadata_file  : int
        :param physiological_file       : Physiological file object to link the electrode info to
        :param blake2                   : blake2b hash of the event file
         :type blake2                   : str
        :param electrode_ids            : blake2b hash of the event file
         :type electrode_ids            : str
        """

        # define modality (MEG, iEEG, EEG)
        try:
            modality = next(
                k for k in electrode_metadata.keys()
                if k.endswith('CoordinateSystem')
            ).rstrip('CoordinateSystem')
            modality_id = self.physiological_coord_system_db.grep_coord_system_modality_from_name(modality.lower())
            if modality_id is None:
                print(f"Modality {modality} unknown in DB")
                # force default
                raise IndexError
        except Exception:
            modality_id = self.physiological_coord_system_db.grep_coord_system_modality_from_name("Not registered")

        # type (Fiducials, AnatomicalLandmark, HeadCoil, DigitizedHeapPoints)
        try:
            coord_system_type = next(
                k for k in electrode_metadata.keys()
                if k.endswith('CoordinateSystem') and not k.startswith(modality)
            ).rstrip('CoordinateSystem')
            type_id = self.physiological_coord_system_db.grep_coord_system_type_from_name(coord_system_type)
            if type_id is None:
                print(f"Type {coord_system_type} unknown in DB")
                # force default
                raise IndexError
        except Exception:
            coord_system_type = None
            type_id = self.physiological_coord_system_db.grep_coord_system_type_from_name("Not registered")

        # unit
        try:
            unit_data = electrode_metadata[f'{modality}CoordinateUnits']
            unit_id = self.physiological_coord_system_db.grep_coord_system_unit_from_symbol(unit_data)
            if unit_id is None:
                print(f"Unit {unit_data} unknown in DB")
                # force default
                raise IndexError
        except Exception:
            unit_id = self.physiological_coord_system_db.grep_coord_system_unit_from_name("Not registered")

        # name
        try:
            coord_system_name = electrode_metadata[f'{modality}CoordinateSystem']
            name_id = self.physiological_coord_system_db.grep_coord_system_name_from_name(coord_system_name)
            if name_id is None:
                print(f"Name {coord_system_name} unknown in DB")
                # force default
                raise IndexError
        except Exception:
            name_id = self.physiological_coord_system_db.grep_coord_system_name_from_name("Not registered")

        # get or create coord system in db
        coord_system_id = self.physiological_coord_system_db.grep_or_insert_coord_system(
            name_id,
            unit_id,
            type_id,
            modality_id,
            str(electrode_metadata_file)
        )

        # define coord system referential points (e.g. LPA, RPA) + points
        is_ok_ref_coords = True
        try:
            if coord_system_type is None:
                raise KeyError
            ref_coords = electrode_metadata[f'{coord_system_type}Coordinates']
            ref_points = {
                ref_key : Point3D(None, *ref_val)
                for ref_key, ref_val in ref_coords.items()
            }
        except Exception:
            # no ref points
            is_ok_ref_coords = False
        # insert ref points if found
        if is_ok_ref_coords:
            # insert ref points
            point_ids = {}
            for rk, rv in ref_points.items():
                p = self.point_3d_db.grep_or_insert_point(rv)
                point_ids[rk] = p.id
            # insert ref point/coord system relations
            self.physiological_coord_system_db.insert_coord_system_point_3d_relation(coord_system_id, point_ids)

        # insert the relation between coordinate file electrode and physio file
        self.physiological_coord_system_db.insert_coord_system_electrodes_relation(
            physiological_file.id,
            coord_system_id,
            electrode_ids
        )

        if blake2:
            # insert blake2b hash of task event file into physiological_parameter_file
            insert_physio_file_parameter(self.env, physiological_file, 'coordsystem_file_json_blake2b_hash', blake2)

    @staticmethod
    def get_additional_members_from_parenthesis_index(string_split, parentheses_to_find, end_index):
        """
        Helper method for determining AdditionalMembers for DB insert

         :param string_split            : String array to search
          :type string_split            : list[str]

         :param parentheses_to_find     : Number of closing parentheses to find
          :type parentheses_to_find     : int

         :param end_index               : Current array index, to look back from
          :type end_index               : int

         :return                        : Number of additional members in group
          :rtype                        : int

         """
        left_to_find = parentheses_to_find
        sub_string_split = string_split[(len(string_split) - end_index - 1):]
        additional_members = 0

        for element_index, split_element in enumerate(sub_string_split):
            left_to_find -= split_element.count(')')
            left_to_find += split_element.count('(') if element_index > 0 else 0
            if left_to_find == 1 and split_element.endswith(')'):
                additional_members += 1
            if left_to_find < 1:
                return additional_members
        return 0

    @dataclass
    class TagGroupMember:
        hed_tag_id: int | None
        has_pairing: bool
        additional_members: int
        tag_value: str | None = None

        def __eq__(self, other):
            return self.hed_tag_id == other.hed_tag_id and \
                self.has_pairing == other.has_pairing and \
                self.additional_members == other.additional_members

    @staticmethod
    def build_hed_tag_groups(hed_union, hed_string):
        """
        Assembles physiological event HED tags.

        :param hed_union            : Union of HED schemas
         :type hed_union            : any

        :param hed_string           : HED string
         :type hed_string           : str

        :return                     : List of HEDTagID groups
         :rtype                     : list[TagGroupMember]
        """
        # TODO: VALIDATE HED TAGS VIA SERVICE
        # hedDict = utilities.assemble_hed_service(data_dir, event_tsv, event_json)

        # NOT SUPPORTED: DEFS & VALUES

        # TODO: TRANSACTION THAT ROLLS BACK IF HED_TAG_ID LIST MATCHES (CONSIDER ADDING ADDITIONAL
        # + HP TO IT)

        string_split = hed_string.split(',')
        group_depth = 0
        tag_groups = []
        tag_group = []

        for element_index, split_element in enumerate(string_split.__reversed__()):
            additional_members = 0
            if group_depth == 0:
                if len(tag_group) > 0:
                    tag_groups.append(tag_group)
                    tag_group = []

            element = split_element.strip()
            right_stripped = element.rstrip(')')
            left_stripped = right_stripped.lstrip('(')
            num_opening_parentheses = len(right_stripped) - len(left_stripped)

            has_pairing = element.startswith('(') and (
                group_depth == 0 or not element.endswith(')')
            )

            if has_pairing:
                additional_members = \
                    Physiological.get_additional_members_from_parenthesis_index(string_split, 1, element_index)

            hed_tag_id = Physiological.get_hed_tag_id_from_name(left_stripped, hed_union)
            tag_group.append(Physiological.TagGroupMember(hed_tag_id, has_pairing, additional_members))

            for i in range(
                0 if group_depth > 0 and element.startswith('(') and element.endswith(')') else 1,
                num_opening_parentheses
            ):
                has_pairing = True
                additional_members = \
                    Physiological.get_additional_members_from_parenthesis_index(string_split, i + 1, element_index)
                tag_group.append(Physiological.TagGroupMember(None, has_pairing, additional_members))
            group_depth += (len(element) - len(right_stripped))
            group_depth -= num_opening_parentheses
        if len(tag_group) > 0:
            tag_groups.append(tag_group)

        return tag_groups

    @staticmethod
    def standardize_row_columns(row):
        """
        Standardizes LORIS-recognized events.tsv columns to their DB column name

       :param row                  : A row item from the events.tsv
        :type row                  : dict

       :return: Standardized row
        :rtype: dict
       """
        standardized_row = {}
        recognized_event_fields = [
            'Onset', 'Duration', 'TrialType',
            'ResponseTime', 'EventCode',
            'EventSample', 'EventType'
        ]
        for column_name in row:
            column_value = row[column_name]
            if column_value is None:
                continue

            stripped_name = column_name.replace('_', '')
            try:
                field_index = list(map(lambda f: f.lower(), recognized_event_fields)).index(stripped_name)
                column = recognized_event_fields[field_index]
            except ValueError:
                column = 'EventValue' if (column_name == 'value' or column_name == 'event_value') else column_name
            standardized_row[column] = column_value

        return standardized_row

    @staticmethod
    def filter_inherited_tags(row, tag_groups, dataset_tag_dict, file_tag_dict):
        """
        Filters for tags inherited from events.json

        :param row                  : A row item from the events.tsv
         :type row                  : dict
        :param tag_groups           : Tag groups to filter
         :type tag_groups           : list[list[TagGroupMember]
        :param dataset_tag_dict     : Dict of dataset-inherited HED tags
         :type dataset_tag_dict     : dict
        :param file_tag_dict        : Dict of subject-inherited HED tags
         :type file_tag_dict        : dict

        :return: List of tag groups not inherited from events.json
         :rtype: list[list[TagGroupMember]
        """
        # TODO: Overwrite dataset tags with file tags
        # Only dataset tags currently supported until overwrite
        standardized_row = Physiological.standardize_row_columns(row)
        inherited_tag_groups = reduce(lambda a, b: a + b, [
            dataset_tag_dict[column_name][standardized_row[column_name]]
            for column_name in standardized_row
            if column_name in dataset_tag_dict
            and standardized_row[column_name] in dataset_tag_dict[column_name]
        ], [])
        return filter(
            lambda tag_group: not any(
                len(tag_group) == len(inherited_tag_group) and all(
                    tag_group[i] == inherited_tag_group[i]
                    for i in range(len(tag_group))
                )
                for inherited_tag_group in inherited_tag_groups
            ),
            tag_groups
        )

    @staticmethod
    def get_hed_tag_id_from_name(tag_string, hed_union):
        hed_tag_id = None
        if tag_string is not None:
            leaf_node = tag_string.split('/')[-1]  # LIMITED SUPPORT FOR NOW - NO VALUES OR DEFS
            if len(tag_string) > 0:
                hed_tag = next(filter(lambda tag: tag['Name'] == leaf_node, list(hed_union)), None)
                if not hed_tag:
                    print(f'ERROR: UNRECOGNIZED HED TAG: {tag_string}')
                    raise
                hed_tag_id = hed_tag['ID']
        return hed_tag_id
