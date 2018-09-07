"""This class performs database queries for BIDS physiological dataset (EEG, MEG...)
"""

import time
import sys


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

        # get output type ID for the physiological file
        output_type = physiological.get_output_type_id(derivatives)

        # grep a PhysiologicalFileID based on a blake2b hash
        file_id = physiological.grep_file_id_from_hash(blake2)

        # grep the modality ID for a BIDS modality
        modality_id = physiological.get_modality(bids_modality)

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

    def get_modality(self, modality):
        """
        Greps the modality ID from the physiological_modality table. If
        db_modality cannot be found, the script will exit with error message
        and error code.

        :param modality: name of the modality to look for
         :type modality: str

        :return: modality ID from the physiological_modality
         :rtype: int
        """

        db_modality = self.db.pselect(
            query="SELECT PhysiologicalModalityID "
                  "FROM physiological_modality "
                  "WHERE PhysiologicalModality = %s",
            args=(modality,)
        )

        # if the modality cannot be found in the database, exit now
        if not db_modality:
            message = "\nERROR: Modality " + modality + " does not " \
                      "exist in physiological_modality database table\n"
            print(message)
            sys.exit(lib.exitcode.SELECT_FAILURE)

        modality_id = db_modality[0]['PhysiologicalModalityID']

        return modality_id

    def get_file_type(self, file):
        """
        Greps all file types defined in the ImagingFileTypes table and check
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
            if type['type'] in file:
                file_type = type['type']

        # exits if could not find a file type
        if not file_type:
            message = "\nERROR: File type for " + file + " does not exist " \
                      "in ImagingFileTypes database table\n"
            print(message)
            sys.exit(lib.exitcode.SELECT_FAILURE)

        return file_type

    def get_output_type_id(self, derivatives):
        """
        Returns the PhysiologicalOutputTypeID for derivatives or raw datasets.

        :param derivatives: whether to fetch the PhysiologicalOutputTypeID for
                            'derivatives' (if set) or 'raw' (if not set)
         :type derivatives: bool

        :return: PhysiologicalOutputTypeID associated to the output type
         :rtype: int
        """

        query = "SELECT PhysiologicalOutputTypeID "  + \
                  " FROM physiological_output_type " + \
                  " WHERE OutputType = %s"
        where = ['derivatives',] if derivatives else ['raw',]
        output_types = self.db.pselect(query=query, args=where)

        return output_types[0]['PhysiologicalOutputTypeID']

    def grep_file_id_from_hash(self, blake2b_hash):
        """
        Greps the physiological file ID from the physiological_file table. If
        it cannot be found, the method will return None.

        :param blake2b_hash: blake2b hash
         :type blake2b_hash: str

        :return: physiological file ID and physiological file path
         :rtype: int
        """

        query = "SELECT pf.PhysiologicalFileID, pf.File "     \
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
            'PhysiologicalFileID', 'ParameterTypeID', 'InsertTime', 'Value'
        )
        parameter_file_values = (
            physiological_file_id, parameter_type_id, int(time.time()), value
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
            parameter_desc = parameter_name + " magically created by" \
                             " lib.physiological python class"
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
                    " FROM physiological_electrode"
                    " WHERE PhysiologicalFileID = %s",
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

    def grep_event_from_physiological_file_id(self, physiological_file_id):
        """
        Greps all entries present in the physiological_task_event table for a
        given PhysiologicalFileID and returns its result.

        :param physiological_file_id: physiological file's ID
         :type physiological_file_id: int

        :return: tuple of dictionaries with one entry in the tuple
                 corresponding to one entry in physiological_task_event
         :rtype: tuple
        """

        results = self.db.pselect(
            query="SELECT * "
                  " FROM physiological_task_event "
                  " WHERE PhysiologicalFileID = %s",
            args=(physiological_file_id,)
        )

        return results

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
            'PhysiologicalFileID', 'Name',     'X', 'Y', 'Z',
            'Type',                'Material', 'File'
        )
        electrode_values = []
        for row in electrode_data:
            values_tuple = (
                str(physiological_file_id),
                row['name'],
                row['x'],
                row['y'],
                row['z'],
                row['type'],
                row['material'],
                electrode_file
            )
            electrode_values.append(values_tuple)

        # insert into physiological_electrode table
        self.db.insert(
            table_name   = 'physiological_electrode',
            column_names = electrode_fields,
            values       = electrode_values
        )

        # insert blake2b hash of electrode file into physiological_parameter_file
        self.insert_physio_parameter_file(
            physiological_file_id, 'electrode_file_blake2b_hash', blake2
        )

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
            'SoftwareFilters',           'File'
        )
        channel_values = []
        for row in channel_data:
            physio_channel_type = self.db.pselect(
                query="SELECT PhysiologicalChannelTypeID "
                      " FROM physiological_channel_type "
                      " WHERE ChannelType = %s",
                args=(row['type'],)
            )
            physio_status_type_id = None
            if 'status' in row.keys():
                result = self.db.pselect(
                    query="SELECT PhysiologicalStatusTypeID "
                          " FROM physiological_status_type "
                          " WHERE ChannelStatus = %s",
                    args=(row['status'],)
                )
                physio_status_type_id = result[0]['PhysiologicalStatusTypeID']
            optional_fields = (
                'description',        'sampling_frequency', 'low_cutoff',
                'high_cutoff',        'manual',             'notch',
                'status_description', 'software_filters',   'unit'
            )
            for field in optional_fields:
                if field not in row.keys():
                    row[field] = None
                if field == 'manual' and row[field] == 'TRUE':
                    row[field] = 1
                elif field == 'manual' and row[field] == 'FALSE':
                    row[field] = 0
                    
            values_tuple = (
                str(physiological_file_id),
                str(physio_channel_type[0]['PhysiologicalChannelTypeID']),
                physio_status_type_id,
                row['name'],
                row['description'],
                row['sampling_frequency'],
                row['low_cutoff'],
                row['high_cutoff'],
                row['manual'],
                row['notch'],
                row['status_description'],
                row['unit'],
                row['software_filters'],
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

        event_fields = (
            'PhysiologicalFileID', 'Onset',     'Duration', 'TrialType',
            'ResponseTime',        'EventCode', 'Sample',   'File'
        )
        event_values = []
        for row in event_data:
            optional_fields = (
                'trial_type', 'response_time',
                'event_code', 'sample'
            )
            for field in optional_fields:
                if field not in row.keys():
                    row[field] = None
            # TODO: remove the following if once received confirmation from
            # TODO: James it was an error.
            if "NaN" in row['duration']:
                row['duration'] = 0
            values_tuple = (
                str(physiological_file_id),
                row['onset'],
                row['duration'],
                row['trial_type'],
                row['response_time'],
                row['event_code'],
                row['sample'],
                event_file
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
