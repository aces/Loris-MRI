"""This class performs database queries for the physiological_event_parameter table"""


__license__ = "GPLv3"


class PhysiologicalEventParameter:

    def __init__(self, db, verbose):
        """
        Constructor method for the PhysiologicalEventParameter class.

        :param db                 : Database class object
         :type db                 : object
        :param verbose            : whether to be verbose
         :type verbose            : bool
        """

        self.db = db
        self.table = 'physiological_event_parameter'
        self.verbose = verbose

    def insert(self, event_file_id, parameter_name, description, long_name, units, is_categorical, hed):
        """
        Inserts a new entry in the physiological_event_parameter table.

        :param event_file_id : event file's ID
         :type event_file_id : int

        :param parameter_name    : Name of the event parameter
         :type parameter_name    : string 

        :param description       : Description of the events
         :type description       : string 

        :param long_name         : Full name of the event parameter
         :type long_name         : string

        :param units             : Event parameter's units
         :type units             : string
        
        :param is_categorical    : Whether event has categorical levels ('Y' || 'N')
         :type is_categorical    : string

        :param hed               : Event parameter's HED tag if not categorical
         :type hed               : string

        :return                      : id of the row inserted
         :rtype                      : int
        """

        return self.db.insert(
            table_name   = self.table,
            column_names = ('EventFileID', 'ParameterName', 'Description', 'LongName',
                            'Units', 'isCategorical', 'HED'),
            values       = (event_file_id, parameter_name, description, long_name, units, is_categorical, hed),
            get_last_id  = True
        )
