"""This class performs database queries for the physiological_file table"""


__license__ = "GPLv3"


class PhysiologicalFile:

    def __init__(self, db, verbose):
        """
        Constructor method for the PhysiologicalFile class.

        :param db                 : Database class object
         :type db                 : object
        :param verbose            : whether to be verbose
         :type verbose            : bool
        """

        self.db = db
        self.table = 'physiological_file'
        self.verbose = verbose

    def insert(self, physiological_modality_id, physiological_output_type_id, session_id,
               file_type, acquisition_time, inserted_by_user, file_path):
        """
        Inserts a new entry in the physiological_event_file table.


        :param physiological_modality_id    : Physiological modality ID
         :type physiological_modality_id    : int
        :param physiological_output_type_id : Physiological output type ID
         :type physiological_output_type_id : int
        :param session_id                   : Session ID
         :type session_id                   : int
        :param file_type                    : File Type
         :type file_type                    : string
        :param acquisition_time             : Acquisition Time
         :type acquisition_time             : string
        :param inserted_by_user             : Inserted By User
         :type inserted_by_user             : string
        :param file_path                    : File path
         :type file_path                    : string


        :return                  : id of the row inserted
         :rtype                  : int
        """

        return self.db.insert(
            table_name   = self.table,
            column_names = (
                'PhysiologicalModalityID',
                'PhysiologicalOutputTypeID',
                'SessionID',
                'FileType',
                'AcquisitionTime',
                'InsertedByUser',
                'FilePath'
            ),
            values       = (
                physiological_modality_id, physiological_output_type_id, session_id,
                file_type, acquisition_time, inserted_by_user, file_path
            ),
            get_last_id  = True
        )

    def grep_file_id_from_hash(self, blake2b_hash):
        """
             Greps the physiological file ID from the physiological_file table. If
             it cannot be found, the method will return None.

             :param blake2b_hash: blake2b hash
              :type blake2b_hash: str

             :return: physiological file ID and physiological file path
              :rtype: int
             """

        query = "SELECT pf.PhysiologicalFileID, pf.FilePath " \
                "FROM physiological_file AS pf " \
                "JOIN physiological_parameter_file " \
                "USING (PhysiologicalFileID) " \
                "JOIN parameter_type " \
                "USING (ParameterTypeID) " \
                "WHERE Value=%s"

        results = self.db.pselect(query=query, args=(blake2b_hash,))

        # return the results
        return results[0] if results else None
