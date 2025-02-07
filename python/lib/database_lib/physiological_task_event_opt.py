"""This class performs database queries for the physiological_task_event_opt table"""


__license__ = "GPLv3"


class PhysiologicalTaskEventOpt:

    def __init__(self, db, verbose):
        """
        Constructor method for the PhysiologicalTaskEventOpt class.

        :param db                : Database class object
         :type db                 : object
        :param verbose            : whether to be verbose
         :type verbose            : bool
        """

        self.db = db
        self.table = 'physiological_task_event_opt'
        self.verbose = verbose

    def insert(self, target_id, property_name, property_value, get_last_id=True):
        """
        Inserts a new entry in the physiological_task_event_opt table.

        :param target_id            : PhysiologicalTaskEventID from physiological_task_event table
         :type target_id            : int
        :param property_name        : Column name
         :type property_name        : str
        :param property_value       : Column value
         :type property_value       : str | None
        :param get_last_id          : Returns id of insertion if true
         :type get_last_id          : bool

        :return                     : id of the row inserted
         :rtype                     : int | None
        """
        column_names = (
            'PhysiologicalTaskEventID',
            'PropertyName',
            'PropertyValue'
        )
        values = (
            target_id,
            property_name,
            property_value
        )
        return self.db.insert(
            table_name=self.table,
            column_names=column_names,
            values=values,
            get_last_id=get_last_id
        )
