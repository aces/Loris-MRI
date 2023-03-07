"""This class performs database queries for BIDS physiological dataset (EEG, MEG...)"""

import sys
import re
import os
import subprocess
import lib.exitcode
import lib.utilities as utilities
from lib.database_lib.physiologicaleventfile import PhysiologicalEventFile
from lib.database_lib.physiologicaleventparameter import PhysiologicalEventParameter
from lib.database_lib.physiologicaleventparametercategorylevel import PhysiologicalEventParameterCategoryLevel
from lib.database_lib.physiological_coord_system import PhysiologicalCoordSystem
from lib.database_lib.point_3d import Point3DDB
from lib.point_3d import Point3D


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

        self.physiological_event_file_obj                     = PhysiologicalEventFile(self.db, self.verbose)
        self.physiological_event_parameter_obj                = PhysiologicalEventParameter(self.db, self.verbose)
        self.physiological_event_parameter_category_level_obj = \
            PhysiologicalEventParameterCategoryLevel(self.db, self.verbose)
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
        """
        Greps the physiological file ID from the physiological_file table. If
        it cannot be found, the method will return None.

        :param blake2b_hash: blake2b hash
         :type blake2b_hash: str

        :return: physiological file ID and physiological file path
         :rtype: int
        """

        query = "SELECT pf.PhysiologicalFileID, pf.FilePath "     \
                "FROM physiological_file AS pf "     \
                "JOIN physiological_parameter_file " \
                "USING (PhysiologicalFileID) "   \
                "JOIN parameter_type "               \
                "USING (ParameterTypeID) "       \
                "WHERE Value=%s"

        results = self.db.pselect(query=query, args=(blake2b_hash,))

        # return the results
        return results[0] if results else None

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

        # insert info from eeg_file_info into physiological_file
        file_fields = ()
        file_values = ()
        for key, value in eeg_file_info.items():
            file_fields = file_fields + (key,)
            file_values = file_values + (value,)
        physiological_file_id = self.db.insert(
            table_name   = 'physiological_file',
            column_names = file_fields,
            values       = [file_values],
            get_last_id  = True
        )

        for key, value in eeg_file_data.items():
            self.insert_physio_parameter_file(
                physiological_file_id, key, value
            )

        return physiological_file_id

    def insert_physio_parameter_file(self, physiological_file_id,
                                     parameter_name, value):
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
        """
        # Gather column name & values to insert into
        # physiological_parameter_file
        parameter_type_id = self.get_parameter_type_id(parameter_name)
        parameter_file_fields = (
            'PhysiologicalFileID', 'ParameterTypeID', 'Value'
        )
        parameter_file_values = (
            physiological_file_id, parameter_type_id, value
        )
        self.db.insert(
            table_name='physiological_parameter_file',
            column_names=parameter_file_fields,
            values=parameter_file_values
        )

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
            col_names = (
                'Name', 'Type', 'Description', 'SourceFrom', 'Queryable'
            )
            parameter_desc = parameter_name + " magically created by lib.physiological python class"
            source_from    = 'physiological_parameter_file'
            values = (
                parameter_name, 'text', parameter_desc, source_from, 0
            )
            parameter_type_id = self.db.insert(
                table_name   = 'parameter_type',
                column_names = col_names,
                values       = values,
                get_last_id  = True
            )

            # link the parameter_type_id to a parameter type category
            category_id = self.get_parameter_type_category_id()
            self.db.insert(
                table_name   = 'parameter_type_category_rel',
                column_names = ('ParameterTypeCategoryID', 'ParameterTypeID'),
                values       = (category_id, parameter_type_id),
                get_last_id  = False
            )

        return parameter_type_id

    def get_parameter_type_category_id(self):
        """
        Greps ParameterTypeCategoryID from parameter_type_category table.
        If no ParameterTypeCategoryID was found, it will return None.

        :return: ParameterTypeCategoryID
         :rtype: int
        """

        category_result = self.db.pselect(
            query='SELECT ParameterTypeCategoryID '
                  'FROM parameter_type_category '
                  'WHERE Name = %s ',
            args=('Electrophysiology Variables',)
        )

        if not category_result:
            return None

        return category_result[0]['ParameterTypeCategoryID']

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
        electrode_values = []
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
            electrode_values.append(values_tuple)

            inserted_electrode_id = self.db.insert(
                table_name   = 'physiological_electrode',
                column_names = electrode_fields,
                values       = electrode_values,
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

        # insert blake2b hash of task event file into physiological_parameter_file
        self.insert_physio_parameter_file(
            physiological_file_id,
            'coordsystem_file_json_blake2b_hash',
            blake2
        )

    def insert_event_metadata(self, event_metadata, event_metadata_file, physiological_file_id, blake2):
        """
        Inserts the events metadata information read from the file *events.json
        into the physiological_event_file, physiological_event_parameter
        and physiological_event_parameter_category_level tables, linking it to the 
        physiological file ID already inserted in physiological_file.

        :param event_metadata      : list with dictionaries of events
                                          metadata to insert into the database
         :type event_metadata      : list
        :param event_metadata_file : name of the event metadata file
         :type event_file          : str
        :param physiological_file_id    : PhysiologicalFileID to link the event info to
         :type physiological_file_id    : int
        :param blake2                   : blake2b hash of the event file
         :type blake2                   : str

        :return: event file id
         :rtype: int
        """

        event_file_id = self.physiological_event_file_obj.insert(
            physiological_file_id,
            'json',
            event_metadata_file
        )

        for parameter in event_metadata:
            parameterName = parameter
            description = event_metadata[parameter]['Description'] \
                if 'Description' in event_metadata[parameter] \
                else None
            longName = event_metadata[parameter]['LongName'] if 'LongName' in event_metadata[parameter] else None
            units = event_metadata[parameter]['Units'] if 'Units' in event_metadata[parameter] else None
            if 'Levels' in event_metadata[parameter]:
                isCategorical = 'Y'
                valueHED = None
            else:
                isCategorical = 'N'
                valueHED = event_metadata[parameter]['HED'] if 'HED' in event_metadata[parameter] else None

            event_parameter_id = self.physiological_event_parameter_obj.insert(
                str(event_file_id),
                parameterName,
                description,
                longName,
                units,
                isCategorical,
                valueHED
            )

            if isCategorical == 'Y':
                for level in event_metadata[parameter]['Levels']:
                    levelName = level
                    levelDescription = event_metadata[parameter]['Levels'][level]
                    levelHED = event_metadata[parameter]['HED'][level] \
                        if level in event_metadata[parameter]['HED'] \
                        else None

                    self.physiological_event_parameter_category_level_obj.insert(
                        str(event_parameter_id),
                        levelName,
                        levelDescription,
                        levelHED
                    )

        # insert blake2b hash of task event file into physiological_parameter_file
        self.insert_physio_parameter_file(
            physiological_file_id, 'event_file_json_blake2b_hash', blake2
        )

    def insert_event_file(self, event_data, event_file, physiological_file_id,
                          blake2):
        """
        Inserts the event information read from the file *events.tsv
        into the physiological_task_event table, linking it to the
        physiological file ID already inserted in physiological_file.

        :param event_data           : list with dictionaries of events
                                      information to insert into
                                      physiological_task_event
         :type event_data           : list
        :param event_file           : name of the event file
         :type event_file           : str
        :param physiological_file_id: PhysiologicalFileID to link the event info to
         :type physiological_file_id: int
        :param blake2               : blake2b hash of the task event file
         :type blake2               : str
        """

        event_file_id = self.physiological_event_file_obj.insert(
            physiological_file_id,
            'tsv',
            event_file
        )

        event_fields = (
            'PhysiologicalFileID', 'EventFileID', 'Onset', 'Duration',   
            'TrialType', 'ResponseTime', 'EventCode', 'EventValue', 
            'EventSample', 'EventType'
        )

        event_values = []
        for row in event_data:
            optional_fields = (
                'trial_type',  'response_time', 'event_code',
                'event_value', 'event_sample',  'event_type',
                'value',       'sample'
            )
            for field in optional_fields:
                if field not in row.keys():
                    row[field] = None

            duration = 0
            if (type(row['duration']) == int or type(row['duration']) == float):
                duration = row['duration']

            sample = None
            if type(row['event_sample']) == int or type(row['event_sample']) == float:
                sample = row['event_sample']
            if row['sample'] and (type(row['sample']) == int or type(row['sample']) == float):
                sample = row['sample']

            event_value = None
            if row['event_value']:
                event_value = str(row['event_value'])
            elif row['value']:
                event_value = str(row['value'])

            response_time = None
            if type(row['response_time']) == int or type(row['response_time']) == float:
                response_time = row['response_time']

            values_tuple = (
                str(physiological_file_id),
                str(event_file_id),
                row['onset'],
                duration,
                row['trial_type'],
                response_time,
                row['event_code'],
                event_value,
                sample,
                row['event_type']
            )
            event_values.append(values_tuple)

        self.db.insert(
            table_name   = 'physiological_task_event',
            column_names = event_fields,
            values       = event_values
        )

        # insert blake2b hash of task event file into physiological_parameter_file
        self.insert_physio_parameter_file(
            physiological_file_id, 'event_file_blake2b_hash', blake2
        )

    def insert_event_assembled_hed_tags(self, data_dir, event_tsv, event_json, physio_file_id):
        """
        Assembles physiological event HED annotations.

        :param event_tsv           : path to event data file
         :type event_tsv           : str
        
        :param event_json           : path to the event metadata file
         :type event_json           : str

        :param physio_file_id : Physiological file's ID
         :type physio_file_id       : int
        """
        hedDict = utilities.assemble_hed_service(data_dir, event_tsv, event_json)

        # get EventFileID from FilePath
        physiological_event_file_obj = PhysiologicalEventFile(self.db, self.verbose)
        event_file_id = physiological_event_file_obj.grep_event_file_id_from_event_path(event_tsv, physio_file_id)

        # get all task events for specified EventFileID
        query = "SELECT PhysiologicalTaskEventID as TaskEventID, Onset " \
                "FROM physiological_task_event " \
                "WHERE EventFileID = %s"
        task_event_data = self.db.pselect(query=query, args=(event_file_id,))

        for index in range(len(task_event_data)):
            eventID = task_event_data[index]['TaskEventID']
            onset = task_event_data[index]['Onset']
            if hedDict[index] and 'onset' in hedDict[index]:
                hedOnset = '{0:.6f}'.format(float(hedDict[index]['onset']))
                if (float(hedOnset) == float(onset)):
                    assembledHED = hedDict[index]['HED_assembled']
                    updateAssembledHED = "UPDATE physiological_task_event " \
                        "SET AssembledHED = %s " \
                        "WHERE PhysiologicalTaskEventID = %s"
                    self.db.update(query=updateAssembledHED, args=(assembledHED, eventID,))

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
            physio_file_id, 'electrophyiology_chunked_dataset_path'
        )
        chunk_path = results['Value'] if results else None

        # determine which script to run based on the file type
        command   = None
        script    = None
        if not chunk_path:
            file_type    = self.grep_file_type_from_file_id(physio_file_id)
            file_path    = self.grep_file_path_from_file_id(physio_file_id)
            # the bids_rel_dir is the first two directories in file_path (
            # bids_imports/BIDS_dataset_name_BIDSVersion)
            bids_rel_dir   = file_path.split('/')[0] + '/' + file_path.split('/')[1]
            chunk_root_dir = data_dir + bids_rel_dir + '_chunks' + '/'
            # the final chunk path will be /data/%PROJECT%/data/bids_imports
            # /BIDS_dataset_name_BIDSVersion_chunks/EEG_FILENAME.chunks
            chunk_path = chunk_root_dir + os.path.splitext(os.path.basename(file_path))[0] + '.chunks'
            if file_type == 'set':
                script = os.environ['LORIS_MRI'] + '/python/react-series-data-viewer/eeglab_to_chunks.py'
                command = 'python ' + script + ' ' + data_dir + file_path + ' --destination ' + chunk_root_dir
            elif file_type == 'edf':
                script = os.environ['LORIS_MRI'] + '/python/react-series-data-viewer/edf_to_chunks.py'
                command = 'python ' + script + ' ' + data_dir + file_path + ' --destination ' + chunk_root_dir

        # chunk the electrophysiology dataset if a command was determined above
        if command:
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

            if os.path.isdir(chunk_path):
                self.insert_physio_parameter_file(
                    physiological_file_id = physio_file_id,
                    parameter_name = 'electrophyiology_chunked_dataset_path',
                    value = chunk_path.replace(data_dir, '')
                )
