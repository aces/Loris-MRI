"""This class performs database queries for the notification_spool table"""

import datetime

__license__ = "GPLv3"


class Notification:

    def __init__(self, db, verbose, notification_type, notification_origin, process_id):
        """
        Constructor method for the Notification class.

        :param db                 : Database class object
         :type db                 : object
        :param verbose            : whether to be verbose
         :type verbose            : bool
        :param notification_type  : notification type to use for the notification_spool table
         :type notification_type  : str
        :param notification_origin: notification origin to use for the notification_spool table
         :type notification_origin: str
        :param process_id         : process ID to use for the notification_spool table
         :type process_id         : str
        """

        self.db      = db
        self.verbose = verbose

        self.notification_type   = notification_type
        self.notification_origin = notification_origin
        self.process_id          = process_id

    def write_to_notification_spool(self, message, is_error, is_verbose, center_id=None):
        """
        Insert a row in the notification_spool table.

        :param message   : message to be inserted in the notification_spool table
         :type message   : str
        :param is_error  : whether the notification is an error or not ('Y' or 'N')
         :type is_error  : str
        :param is_verbose: whether the notification is verbose or not ('Y' or 'N')
         :type is_verbose: str
        :param center_id : the CenterID associated with the notification when applicable
         :type center_id : int
        :return:
        """

        type_id = self.db.grep_id_from_lookup_table(
            id_field_name='NotificationTypeID',
            table_name='notification_types',
            where_field_name='Type',
            where_value=self.notification_type,
            insert_if_not_found=True
        )

        col_names = (
            'NotificationTypeID', 'TimeSpooled', 'Message', 'Origin',
            'ProcessID',          'Error',       'Verbose'
        )
        values = (
            type_id,         datetime.datetime.now(),  message,   self.notification_origin,
            self.process_id, is_error,                 is_verbose
        )

        if center_id:
            col_names = col_names + ('CenterID',)
            values    = values + (center_id,)

        self.db.insert(
            table_name   = 'notification_spool',
            column_names = col_names,
            values       = values
        )