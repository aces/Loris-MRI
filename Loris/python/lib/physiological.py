"""This class performs database queries for BIDS physiological dataset (EEG, MEG...)"""

import sys
import re
import os
import subprocess
from functools import reduce

import lib.exitcode
from dataclasses import dataclass
from lib.database_lib.parameter_type import ParameterType
from lib.database_lib.physiological_file import PhysiologicalFile
from lib.database_lib.physiological_event_file import PhysiologicalEventFile
from lib.database_lib.physiological_task_event import PhysiologicalTaskEvent
from lib.database_lib.physiological_task_event_opt import PhysiologicalTaskEventOpt
from lib.database_lib.physiological_task_event_hed_rel import PhysiologicalTaskEventHEDRel
from lib.database_lib.bids_event_mapping import BidsEventMapping
from lib.database_lib.physiological_parameter_file import PhysiologicalParameterFile
from lib.database_lib.physiological_coord_system import PhysiologicalCoordSystem
from lib.database_lib.point_3d import Point3DDB
from lib.point_3d import Point3D
from lib.database_lib.config import Config

__license__ = "GPLv3"


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

        physiological = Physiological(db, verbose)

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

    def __init__(self, db, verbose):
        """
        Constructor method for the Physiological class.

        :param db     : Database class object
         :type db     : object
        :param verbose: whether to be verbose
         :type verbose: bool
        """

        self.db      = db
        self.verbose = verbose
        self.config_db_obj = Config(self.db, self.verbose)

        self.physiological_event_file_obj                   = PhysiologicalEventFile(self.db, self.verbose)
        self.physiological_task_event                       = PhysiologicalTaskEvent(self.db, self.verbose)
        self.physiological_task_event_opt                   = PhysiologicalTaskEventOpt(self.db, self.verbose)
        self.physiological_task_event_hed_rel               = PhysiologicalTaskEventHEDRel(self.db, self.verbose)
        self.bids_event_mapping_obj                         = BidsEventMapping(self.db, self.verbose)
        self.physiological_physiological_file_obj           = PhysiologicalFile(self.db, self.verbose)
        self.physiological_physiological_parameter_file     = PhysiologicalParameterFile(self.db, self.verbose)
        self.parameter_type_obj                             = ParameterType(self.db, self.verbose)
        self.physiological_coord_system_db = PhysiologicalCoordSystem(self.db, self.verbose)
        self.point_3d_db = Point3DDB(self.db, self.verbose)

    def determine_file_type(self, file):
        """
        Greps all file types defined in the ImagingFileTypes table and checks
        if the file matches one of the file type. If no match is found, the
        script will exit with error message and error code.

        :param file: file's name
         "type file: str

        :return: file's type
         :rtype: str
        """

        imaging_file_types = self.db.pselect(
            query="SELECT type FROM ImagingFileTypes"
        )

        # if the file type cannot be found in the database, exit now
        file_type = None
        for type in imaging_file_types:
            regex_match = r'' + type['type'] + r'(\.gz)?$'
            if re.search(regex_match, file):
                file_type = type['type']

        # exits if could not find a file type
        if not file_type:
            message = "\nERROR: File type for " + file + " does not exist " \
                      "in ImagingFileTypes database table\n"
            print(message)
            sys.exit(lib.exitcode.SELECT_FAILURE)

        return file_type

    def grep_file_id_from_hash(self, blake2b_hash):
        return self.physiological_physiological_file_obj.grep_file_id_from_hash(blake2b_hash)

    def insert_physiological_file(self, eeg_file_info, eeg_file_data):
        """
        Inserts the physiological file and its information into the
        physiological_file and physiological_parameter_file tables.

        :param eeg_file_info: dictionary with values to insert into
                              physiological_file's table
         :type eeg_file_info: dict
        :param eeg_file_data: dictionary with values to insert into
                              physiological_parameter_file's table
         :type eeg_file_data: dict

        :return: physiological file ID
         :rtype: int
        """

        physiological_file_id = self.physiological_physiological_file_obj.insert(
            physiological_modality_id=eeg_file_info['PhysiologicalModalityID'],
            physiological_output_type_id=eeg_file_info['PhysiologicalOutputTypeID'],
            session_id=eeg_file_info['SessionID'],
            file_type=eeg_file_info['FileType'],
            acquisition_time=eeg_file_info['AcquisitionTime'],
            inserted_by_user=eeg_file_info['InsertedByUser'],
            file_path=eeg_file_info['FilePath']
        )

        for key, value in eeg_file_data.items():
            self.insert_physio_parameter_file(
                physiological_file_id, key, value
            )

        return physiological_file_id

    def insert_physio_parameter_file(self, physiological_file_id,
                                     parameter_name, value, project_id=None):
        """
        Insert a row into the physiological_parameter_file table for the
        provided PhysiologicalFileID, parameter Name and Value

        :param physiological_file_id: PhysiologicalFileID
         :type physiological_file_id: int
        :param parameter_name       : Name of the parameter from parameter_type
         :type parameter_name       : str
        :param value                : Value to insert into
                                      physiological_parameter_file
         :type value                : str
        :param project_id           : ProjectID
         :type project_id           : int
        """
        # Gather column name & values to insert into
        # physiological_parameter_file
        parameter_type_id = self.get_parameter_type_id(parameter_name)

        if project_id is None:
            project_id = self.get_project_id(physiological_file_id)
        else:
            physiological_file_id = None

        self.physiological_physiological_parameter_file.insert(
            physiological_file_id=physiological_file_id,
            project_id=project_id,
            parameter_type_id=parameter_type_id,
            value=value
        )

    def get_project_id(self, physiological_file_id):
        """
        Ultimately obtains ProjectID from Project table using PhysiologicalFileID

        :param physiological_file_id    : PhysiologicalFileID
         :type physiological_file_id    : int

        :return: ProjectID
         :rtype: int
        """
        results = self.db.pselect(
            query="SELECT ProjectID "
                  "FROM session AS s "
                  "WHERE s.ID = ("
                  "SELECT SessionID FROM physiological_file "
                  "WHERE PhysiologicalFileID = %s"
                  ")",
            args=(physiological_file_id,)
        )
        return int(results[0]['ProjectID'])

    def get_parameter_type_id(self, parameter_name):
        """
        Greps ParameterTypeID from parameter_type table using parameter_name.
        If no ParameterTypeID were found, will create it in parameter_type.

        :param parameter_name: name of the parameter to look in parameter_type
         :type parameter_name: str

        :return: ParameterTypeID
         :rtype: int
        """

        results = self.db.pselect(
            query="SELECT ParameterTypeID "
                  "FROM parameter_type "
                  "WHERE Name = %s "
                  "AND SourceFrom='physiological_parameter_file'",
            args=(parameter_name,)
        )

        if results:
            # if results, grep the parameter_type_id
            parameter_type_id = results[0]['ParameterTypeID']
        else:
            # if no results, create an entry in parameter_type
            col_names = [
                'Name', 'Type', 'Description', 'SourceFrom', 'Queryable'
            ]
            parameter_desc = parameter_name + " magically created by lib.physiological python class"
            source_from    = 'physiological_parameter_file'
            values = [
                parameter_name, 'text', parameter_desc, source_from, 0
            ]
            parameter_type_id = self.parameter_type_obj.insert_parameter_type(
                dict(zip(col_names, values))
            )

            # link the parameter_type_id to a parameter type category
            category_id = self.parameter_type_obj.get_parameter_type_category_id(
                'Electrophysiology Variables'
            )
            self.parameter_type_obj.insert_into_parameter_type_category_rel(
                category_id,
                parameter_type_id
            )

        return parameter_type_id

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

    def grep_channel_from_physiological_file_id(self, physiological_file_id):
        """
        Greps all entries present in the physiological_channel table for a
        given PhysiologicalFileID and returns its result.

        :param physiological_file_id: physiological file's ID
         :type physiological_file_id: int

        :return: tuple of dictionaries with one entry in the tuple
                 corresponding to one entry in physiological_channel
         :rtype: tuple
        """

        results = self.db.pselect(
            query = "SELECT * "
                    " FROM physiological_channel "
                    " WHERE PhysiologicalFileID = %s",
            args  = (physiological_file_id,)
        )

        return results

    def grep_event_paths_from_physiological_file_id(self, physiological_file_id):
        """
        Gets the FilePath of event files given a physiological_file_id

        :param physiological_file_id : Physiological file's ID
         :type physiological_file_id : int

        :return                      : list of FilePath if any or None
         :rtype                      : list
        """

        event_paths = self.db.pselect(
            query = "SELECT DISTINCT FilePath "
                    "FROM physiological_event_file "
                    "WHERE PhysiologicalFileID = %s",
            args=(physiological_file_id,)
        )

        event_paths = [event_path['FilePath'] for event_path in event_paths]

    def insert_electrode_file(self, electrode_data, electrode_file,
                              physiological_file_id, blake2):
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
        :param physiological_file_id: PhysiologicalFileID to link the
                                      electrode information to
         :type physiological_file_id: int
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
        self.insert_physio_parameter_file(
            physiological_file_id, 'electrode_file_blake2b_hash', blake2
        )
        return electrode_ids

    def insert_channel_file(self, channel_data, channel_file,
                            physiological_file_id, blake2):
        """
        Inserts the channel information read from the file *channels.tsv
        into the physiological_channel table, linking it to the
        physiological file ID already inserted in physiological_file.

        :param channel_data         : list with dictionaries of channels
                                      information to insert into
                                      physiological_channel
         :type channel_data         : list
        :param channel_file         : name of the channel file
         :type channel_file         : str
        :param physiological_file_id: PhysiologicalFileID to link the channel info to
         :type physiological_file_id: int
        :param blake2               : blake2b hash of the channel file
         :type blake2               : str
        """

        channel_fields = (
            'PhysiologicalFileID',       'PhysiologicalChannelTypeID',
            'PhysiologicalStatusTypeID', 'Name',
            'Description',               'SamplingFrequency',
            'LowCutoff',                 'HighCutoff',
            'ManualFlag',                'Notch',
            'StatusDescription',         'Unit',
            'Reference',                 'FilePath'
        )
        channel_values = []
        for row in channel_data:
            physio_channel_type_id = self.db.grep_id_from_lookup_table(
                id_field_name       = 'PhysiologicalChannelTypeID',
                table_name          = 'physiological_channel_type',
                where_field_name    = 'ChannelTypeName',
                where_value         = row['type'],
                insert_if_not_found = False
            )
            physio_status_type_id = None
            if 'status' in row.keys():
                physio_status_type_id = self.db.grep_id_from_lookup_table(
                    id_field_name       = 'PhysiologicalStatusTypeID',
                    table_name          = 'physiological_status_type',
                    where_field_name    = 'ChannelStatus',
                    where_value         = row['status'],
                    insert_if_not_found = False
                )
            optional_fields = (
                'description',        'sampling_frequency', 'low_cutoff',
                'high_cutoff',        'manual',             'notch',
                'status_description', 'units',              'reference'
            )
            for field in optional_fields:
                if field not in row.keys():
                    row[field] = None
                if field == 'manual' and row[field] == 'TRUE':
                    row[field] = 1
                elif field == 'manual' and row[field] == 'FALSE':
                    row[field] = 0
                if field == 'high_cutoff' and row[field] == 'Inf':
                    # replace 'Inf' by the maximum float value to be stored in the
                    # physiological_channel table (a.k.a. 99999.999)
                    row[field] = 99999.999
                if field == 'notch' and row[field] and re.match(r"n.?a",
                                                                row[field],
                                                                re.IGNORECASE):
                    # replace n/a, N/A, na, NA by None which will translate to NULL
                    # in the physiological_channel table
                    row[field] = None

            values_tuple = (
                str(physiological_file_id),
                str(physio_channel_type_id),
                physio_status_type_id,
                row['name'],
                row['description'],
                row['sampling_frequency'],
                row['low_cutoff'],
                row['high_cutoff'],
                row['manual'],
                row['notch'],
                row['status_description'],
                row['units'],
                row['reference'],
                channel_file
            )
            channel_values.append(values_tuple)

        self.db.insert(
            table_name   = 'physiological_channel',
            column_names = channel_fields,
            values       = channel_values
        )

        # insert blake2b hash of channel file into physiological_parameter_file
        self.insert_physio_parameter_file(
            physiological_file_id, 'channel_file_blake2b_hash', blake2
        )

    def insert_electrode_metadata(self, electrode_metadata, electrode_metadata_file,
                                  physiological_file_id, blake2, electrode_ids):
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
        :param physiological_file_id    : PhysiologicalFileID to link the electrode info to
         :type physiological_file_id    : int
        :param blake2                   : blake2b hash of the event file
         :type blake2                   : str
        :param electrode_ids            : blake2b hash of the event file
         :type electrode_ids            : str
        """

        # define modality (MEG, iEEG, EEG)
        try:
            modality = [
                k for k in electrode_metadata.keys()
                if k.endswith('CoordinateSystem')
            ][0].rstrip('CoordinateSystem')
            modality_id = self.physiological_coord_system_db.grep_coord_system_modality_from_name(modality.lower())
            if modality_id is None:
                print(f"Modality {modality} unknown in DB")
                # force default
                raise IndexError
        except (IndexError, KeyError):
            modality_id = self.physiological_coord_system_db.grep_coord_system_modality_from_name("Not registered")

        # type (Fiducials, AnatomicalLandmark, HeadCoil, DigitizedHeapPoints)
        try:
            coord_system_type = [
                k for k in electrode_metadata.keys()
                if k.endswith('CoordinateSystem') and not k.startswith(modality)
            ][0].rstrip('CoordinateSystem')
            type_id = self.physiological_coord_system_db.grep_coord_system_type_from_name(coord_system_type)
            if type_id is None:
                print(f"Type {coord_system_type} unknown in DB")
                # force default
                raise IndexError
        except (IndexError, KeyError):
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
        except (IndexError, KeyError):
            unit_id = self.physiological_coord_system_db.grep_coord_system_unit_from_name("Not registered")

        # name
        try:
            coord_system_name = electrode_metadata[f'{modality}CoordinateSystem']
            name_id = self.physiological_coord_system_db.grep_coord_system_name_from_name(coord_system_name)
            if name_id is None:
                print(f"Name {coord_system_name} unknown in DB")
                # force default
                raise IndexError
        except (IndexError, KeyError):
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
        except (IndexError, KeyError):
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
            physiological_file_id,
            coord_system_id,
            electrode_ids
        )

        # insert blake2b hash of task event file into physiological_parameter_file
        self.insert_physio_parameter_file(
            physiological_file_id,
            'coordsystem_file_json_blake2b_hash',
            blake2
        )

    def insert_event_metadata(self, event_metadata, event_metadata_file, physiological_file_id,
                              project_id, blake2, project_wide, hed_union):
        """
        Inserts the events metadata information read from the file *events.json
        into the physiological_event_file, physiological_event_parameter
        and physiological_event_parameter_category_level tables, linking it to the
        physiological file ID already inserted in physiological_file.

        :param event_metadata           : list with dictionaries of events
                                          metadata to insert into the database
         :type event_metadata           : list
        :param event_metadata_file      : name of the event metadata file
         :type event_file               : str
        :param physiological_file_id    : PhysiologicalFileID to link the event info to
         :type physiological_file_id    : int | None
        :param project_id               : ProjectID
         :type project_id               : int
        :param blake2                   : blake2b hash of the event file
         :type blake2                   : str
        :param project_wide             : ProjectID if true, otherwise PhysiologicalFileID
         :type project_wide             : bool
        :param hed_union                : Union of HED schemas
         :type hed_union                : any

        :return: event file id
         :rtype: int
        """

        event_file_id = self.physiological_event_file_obj.insert(
            physiological_file_id,
            project_id,
            'json',
            event_metadata_file
        )

        tag_dict = self.parse_and_insert_event_metadata(
            event_metadata=event_metadata,
            target_id=project_id if project_wide else physiological_file_id,
            project_wide=project_wide,
            hed_union=hed_union
        )

        # insert blake2b hash of task event file into physiological_parameter_file
        self.insert_physio_parameter_file(
            physiological_file_id,
            'event_file_json_blake2b_hash',
            blake2,
            project_id
        )

        return event_file_id, tag_dict

    def parse_and_insert_event_metadata(self, event_metadata, target_id, project_wide, hed_union):
        tag_dict = {}

        for parameter in event_metadata:
            parameter_name = parameter
            tag_dict[parameter_name] = {}
            # TODO: Commented fields below currently not supported
            # description = event_metadata[parameter]['Description'] \
            #     if 'Description' in event_metadata[parameter] \
            #     else None
            # long_name = event_metadata[parameter]['LongName'] if 'LongName' in event_metadata[parameter] else None
            # units = event_metadata[parameter]['Units'] if 'Units' in event_metadata[parameter] else None
            if 'Levels' in event_metadata[parameter]:
                is_categorical = 'Y'
                # value_hed = None
            else:
                is_categorical = 'N'
                # value_hed = event_metadata[parameter]['HED'] if 'HED' in event_metadata[parameter] else None

            if is_categorical == 'Y':
                for level in event_metadata[parameter]['Levels']:
                    level_name = level
                    tag_dict[parameter_name][level_name] = []
                    level_description = event_metadata[parameter]['Levels'][level]
                    level_hed = event_metadata[parameter]['HED'][level] \
                        if 'HED' in event_metadata[parameter] and level in event_metadata[parameter]['HED'] \
                        else None

                    if level_hed:
                        tag_groups = Physiological.build_hed_tag_groups(hed_union, level_hed)
                        for tag_group in tag_groups:
                            self.insert_hed_tag_group(tag_group, target_id, parameter_name,
                                                      level_name, level_description, True, project_wide)
                        tag_dict[parameter_name][level_name] = tag_groups
        return tag_dict

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

        # TODO: TRANSACTION THAT ROLLS BACK IF HED_TAG_ID LIST MATCHES (CONSIDER ADDING ADDITIONAL + HP TO IT)

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

    def insert_hed_tag_group(self, hed_tag_group, target_id, property_name=None, property_value=None,
                             level_description=None, from_sidecar=False, project_wide=False):
        """
        Assembles physiological event HED tags.

        :param hed_tag_group        : List of TagGroupMember to insert
         :type hed_tag_group        : list[TagGroupMember]

        :param target_id            : ProjectID if project_wide else PhysiologicalEventFileID
         :type target_id            : int

        :param property_name        : PropertyName
         :type property_name        : str | None

        :param property_value       : PropertyValue
         :type property_value       : str | None

        :param level_description    : Tag Description
         :type level_description    : str | None

        :param from_sidecar         : Whether tag comes from an events.json file
         :type from_sidecar         : bool

        :param project_wide         : Whether target is ProjectID or PhysiologicalEventFileID
         :type project_wide         : bool

        """
        pair_rel_id = None
        for hed_tag in hed_tag_group:
            pair_rel_id = self.bids_event_mapping_obj.insert(
                target_id=target_id,
                property_name=property_name,
                property_value=property_value,
                hed_tag_id=hed_tag.hed_tag_id,
                tag_value=hed_tag.tag_value,
                description=level_description,
                has_pairing=hed_tag.has_pairing,
                pair_rel_id=pair_rel_id,
                additional_members=hed_tag.additional_members,
                project_wide=project_wide
            ) if from_sidecar else self.physiological_task_event_hed_rel.insert(
                target_id=target_id,
                hed_tag_id=hed_tag.hed_tag_id,
                tag_value=hed_tag.tag_value,
                has_pairing=hed_tag.has_pairing,
                pair_rel_id=pair_rel_id,
                additional_members=hed_tag.additional_members,
            )

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
                    print('ERROR: UNRECOGNIZED HED TAG: {}'.format(tag_string))
                    raise
                hed_tag_id = hed_tag['ID']
        return hed_tag_id

    def insert_event_file(self, event_data, event_file, physiological_file_id,
                          project_id, blake2, dataset_tag_dict, file_tag_dict,
                          hed_union):
        """
        Inserts the event information read from the file *events.tsv
        into the physiological_task_event table, linking it to the
        physiological file ID already inserted in physiological_file.
        Only called in `eeg.py`.

        :param event_data           : list with dictionaries of events
                                      information to insert into
                                      physiological_task_event
         :type event_data           : list
        :param event_file           : name of the event file
         :type event_file           : str
        :param physiological_file_id: PhysiologicalFileID to link the event info to
         :type physiological_file_id: int
        :param project_id           : ProjectID to link the event info to
         :type project_id           : int
        :param blake2               : blake2b hash of the task event file
         :type blake2               : str
        :param dataset_tag_dict     : Dict of dataset-inherited HED tags
         :type dataset_tag_dict     : dict
        :param file_tag_dict        : Dict of subject-inherited HED tags
         :type file_tag_dict        : dict
        :param hed_union            : Union of HED schemas
         :type hed_union            : any
        """

        event_file_id = self.physiological_event_file_obj.insert(
            physiological_file_id,
            project_id,
            'tsv',
            event_file
        )

        event_fields = (
            'PhysiologicalFileID', 'Onset',     'Duration',   'TrialType',
            'ResponseTime',        'EventCode', 'EventValue', 'EventSample',
            'EventType',           'FilePath',  'EventFileID'
        )
        # known opt fields
        optional_fields = (
            'trial_type', 'response_time', 'event_code',
            'event_value', 'event_sample', 'event_type',
            'value', 'sample', 'duration', 'onset', 'HED'
        )
        # all listed fields
        known_fields = {*event_fields, *optional_fields}

        for row in event_data:
            # nullify not present optional cols
            for field in optional_fields:
                if field not in row.keys():
                    row[field] = None

            # has additional fields?
            additional_fields = {}
            for field in row:
                if field not in known_fields and row[field].lower() != 'nan':
                    additional_fields[field] = row[field]

            # get values of present optional cols
            onset = 0
            if isinstance(row['onset'], (int, float)):
                onset = row['onset']
            else:
                # try casting to float, cannot be n/a
                # should raise an error if not a number
                onset = float(row['onset'])

            duration = 0
            if isinstance(row['duration'], (int, float)):
                duration = row['duration']
            else:
                try:
                    # try casting to float
                    duration = float(row['duration'])
                except ValueError:
                    # value could be 'n/a',
                    # should not raise
                    # let default value (0)
                    pass
            assert duration >= 0

            sample = None
            if isinstance(row['event_sample'], (int, float)):
                sample = row['event_sample']
            if row['sample'] and isinstance(row['sample'], (int, float)):
                sample = row['sample']

            response_time = None
            if isinstance(row['response_time'], (int, float)):
                response_time = row['response_time']

            event_value = None
            if row['event_value']:
                event_value = str(row['event_value'])
            elif row['value']:
                event_value = str(row['value'])

            trial_type = None
            if row['trial_type']:
                trial_type = str(row['trial_type'])

            # insert one event and get its db id
            last_task_id = self.physiological_task_event.insert(
                physiological_file_id=physiological_file_id,
                event_file_id=event_file_id,
                onset=onset,
                duration=duration,
                event_code=row['event_code'],
                event_value=event_value,
                event_sample=sample,
                event_type=row['event_type'],
                trial_type=trial_type,
                response_time=response_time,
            )

            # Insert HED tags after filtering out inherited tags from events.json, so that they are not "duplicated"
            if row['HED'] and len(row['HED']) > 0 and row['HED'] != 'n/a':
                tag_groups = Physiological.build_hed_tag_groups(hed_union, row['HED'])
                tag_groups_without_inherited = Physiological.filter_inherited_tags(
                    row, tag_groups, dataset_tag_dict, file_tag_dict
                )
                for tag_group in tag_groups_without_inherited:
                    self.insert_hed_tag_group(tag_group, last_task_id)

            # if needed, process additional and unlisted
            # fields and send them in secondary table
            if additional_fields:
                # each additional fields is a new entry
                for add_field, add_value in additional_fields.items():
                    self.physiological_task_event_opt.insert(
                        target_id=last_task_id,
                        property_name=add_field,
                        property_value=add_value,
                        get_last_id=False
                    )
        # insert blake2b hash of task event file into physiological_parameter_file
        self.insert_physio_parameter_file(
            physiological_file_id, 'event_file_blake2b_hash', blake2
        )

    def grep_archive_info_from_file_id(self, physiological_file_id):
        """
        Greps the physiological file ID from the physiological_file table. If
        it cannot be found, the method will return None.

        :param physiological_file_id: PhysiologicalFileID to use in the query
         :type physiological_file_id: int

        :return: result of the query from the physiological_archive table
         :rtype: dict
        """

        query = "SELECT * " \
                "FROM physiological_archive " \
                "WHERE PhysiologicalFileID = %s"

        results = self.db.pselect(query=query, args=(physiological_file_id,))

        # return the result
        return results[0] if results else None

    def insert_archive_file(self, archive_info):
        """
        Inserts the archive file of all physiological files (including
        electrodes.tsv, channels.tsv and events.tsv) in the
        physiological_archive table of the database.

        :param archive_info: dictionary with key/value pairs to insert
         :type archive_info: dict
        """

        # insert the archive into the physiological_archive table
        archive_fields = ()
        archive_values = ()
        for key, value in archive_info.items():
            archive_fields = archive_fields + (key,)
            archive_values = archive_values + (value,)
        self.db.insert(
            table_name   = 'physiological_archive',
            column_names = archive_fields,
            values       = archive_values
        )

    def grep_parameter_value_from_file_id(self, physiological_file_id, param_name):
        """
        Greps the value stored in physiological_parameter_file for a given
        PhysiologicalFileID and parameter name (from the parameter_type table).

        :param physiological_file_id: PhysiologicalFileID to use in the query
         :type physiological_file_id: int
        :param param_name           : parameter name to use in the query
         :type param_name           : str

        :return: result of the query from the physiological_parameter_file table
         :rtype: dict
        """

        query = "SELECT Value " \
                "FROM physiological_parameter_file " \
                "JOIN parameter_type USING (ParameterTypeID) " \
                "WHERE PhysiologicalFileID = %s AND Name = %s"

        results = self.db.pselect(
            query = query,
            args  = (physiological_file_id, param_name)
        )

        # return the result
        return results[0] if results else None

    def grep_file_type_from_file_id(self, physiological_file_id):
        """
        Greps the file type stored in the physiological_file table using its
        PhysiologicalFileID.

        :param physiological_file_id: PhysiologicalFileID associated with the file
         :type physiological_file_id: int

        :return: file type of the file with PhysiologicalFileID
         :rtype: str
        """

        query = "SELECT FileType " \
                "FROM physiological_file " \
                "WHERE PhysiologicalFileID = %s"

        results = self.db.pselect(query=query, args=(physiological_file_id,))

        # return the result
        return results[0]['FileType'] if results else None

    def grep_file_path_from_file_id(self, physiological_file_id):
        """
        Greps the file path stored in the physiological_file table using its
        PhysiologicalFileID.

        :param physiological_file_id: PhysiologicalFileID associated with the file
         :type physiological_file_id: int

        :return: file type of the file with PhysiologicalFileID
         :rtype: str
        """

        query = "SELECT FilePath " \
                "FROM physiological_file " \
                "WHERE PhysiologicalFileID = %s"

        results = self.db.pselect(query=query, args=(physiological_file_id,))

        # return the result
        return results[0]['FilePath'] if results else None

    def create_chunks_for_visualization(self, physio_file_id, data_dir):
        """
        Calls chunking scripts if no chunk datasets yet available for
        PhysiologicalFileID based on the file type of the original
        electrophysiology dataset.

        :param physio_file_id: PhysiologicalFileID of the dataset to chunk
         :type physio_file_id: int
        :param data_dir      : LORIS data directory (/data/%PROJECT%/data)
         :type data_dir      : str
        """

        # check if chunks already exists for this PhysiologicalFileID
        results    = self.grep_parameter_value_from_file_id(
            physio_file_id, 'electrophysiology_chunked_dataset_path'
        )
        chunk_path = results['Value'] if results else None

        # No chunks found
        if not chunk_path:
            script    = None
            file_path = self.grep_file_path_from_file_id(physio_file_id)

            chunk_root_dir = self.config_db_obj.get_config("EEGChunksPath")
            if not chunk_root_dir:
                # the bids_rel_dir is the first two directories in file_path (
                # bids_imports/BIDS_dataset_name_BIDSVersion)
                bids_rel_dir   = file_path.split('/')[0] + '/' + file_path.split('/')[1]
                chunk_root_dir = data_dir + bids_rel_dir + '_chunks' + '/'

            # determine which script to run based on the file type
            file_type = self.grep_file_type_from_file_id(physio_file_id)
            if file_type == 'set':
                script = os.environ['LORIS_MRI'] + '/python/react-series-data-viewer/eeglab_to_chunks.py'
                command = 'python ' + script + ' ' + data_dir + file_path + ' --destination ' + chunk_root_dir
            elif file_type == 'edf':
                script = os.environ['LORIS_MRI'] + '/python/react-series-data-viewer/edf_to_chunks.py'
                command = 'python ' + script + ' ' + data_dir + file_path + ' --destination ' + chunk_root_dir

            # chunk the electrophysiology dataset if a command was determined above
            try:
                subprocess.call(
                    command,
                    shell = True,
                    stdout = open(os.devnull, 'wb')
                )
            except subprocess.CalledProcessError as err:
                print(f'ERROR: {script} execution failure. Error was:\n {err}')
                sys.exit(lib.exitcode.CHUNK_CREATION_FAILURE)
            except OSError:
                print('ERROR: ' + script + ' not found')
                sys.exit(lib.exitcode.CHUNK_CREATION_FAILURE)

            # the final chunk path will be /data/%PROJECT%/data/bids_imports
            # /BIDS_dataset_name_BIDSVersion_chunks/EEG_FILENAME.chunks
            chunk_path = chunk_root_dir + os.path.splitext(os.path.basename(file_path))[0] + '.chunks'
            if os.path.isdir(chunk_path):
                self.insert_physio_parameter_file(
                    physiological_file_id = physio_file_id,
                    parameter_name = 'electrophysiology_chunked_dataset_path',
                    value = chunk_path.replace(data_dir, '')
                )
