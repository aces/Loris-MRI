"""This class performs database queries for the physiological_task_event table"""


__license__ = "GPLv3"


class PhysiologicalTaskEvent:

    def __init__(self, db, verbose):
        """
        Constructor method for the PhysiologicalTaskEvent class.

        :param db                : Database class object
         :type db                 : object
        :param verbose            : whether to be verbose
         :type verbose            : bool
        """

        self.db = db
        self.table = 'physiological_task_event'
        self.verbose = verbose

    def insert(self, physiological_file_id, event_file_id, onset, duration,
               event_code, event_value, event_sample, event_type,
               trial_type, response_time, file_path):
        """
        Inserts a new entry in the physiological_task_event_hed_rel table.

        :param physiological_file_id    : PhysiologicalFileID from physiological_file table
         :type physiological_file_id    : int
        :param event_file_id            : EventFileID from physiological_event_file table
         :type event_file_id            : int
        :param onset                    : Event onset time in seconds
         :type onset                    : float
        :param duration                 : Event duration in seconds
         :type duration                 : float
        :param event_code               : Legacy field
         :type event_code               : int | null
        :param event_value              : Value of event (legacy)
         :type event_value              : str
        :param event_sample             : Event onset according to sampling scheme
         :type event_sample             : float | null
        :param event_type               : Legacy field
         :type event_type               : str | null
        :param trial_type               : Event categorization
         :type trial_type               : str | null
        :param response_time            : Response time in seconds
         :type response_time            : float | null
        :param file_path                : Relative path of events.tsv file
         :type file_path                : str

        :return                     : id of the row inserted
         :rtype                     : int
        """
        column_names = (
            'PhysiologicalFileID', 'EventFileID', 'Onset', 'Duration',
            'EventCode', 'EventValue', 'EventSample', 'EventType',
            'TrialType', 'ResponseTime', 'FilePath'
        )
        values = (
            physiological_file_id, event_file_id, onset, duration,
            event_code, event_value, event_sample, event_type,
            trial_type, response_time, file_path
        )
        return self.db.insert(
            table_name=self.table,
            column_names=column_names,
            values=values,
            get_last_id=True
        )
