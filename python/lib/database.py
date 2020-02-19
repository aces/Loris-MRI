"""Allows LORIS database connectivity for LORIS-MRI python code base"""

import MySQLdb
import sys
import mysql.connector
from mysql.connector.cursor import MySQLCursorPrepared

import lib.exitcode


__license__ = "GPLv3"


class Database:
    """
    This class performs common tasks related to database connectivity between
    the LORIS-MRI python code base and the LORIS backend database.

    :Example:

        from lib.database import Database

        db = Database(config.mysql, verbose)

        db.connect()

        # to select data corresponding to specific parameters
        results = db.pselect(
            "SELECT CandID FROM candidate WHERE Active = %s AND Sex = %s",
            ('Y', 'Male')
        )

        # to select data without any specific parameter
        results = db.pselect(
            "SELECT CandID FROM candidate"
        ) # args is optional in db.pselect

        # to insert multiple rows
        db.insert(
            'media',
            ('session_id', 'file_name', 'data_dir'),
            [
                ('6834', 'bla', 'bndjf'),
                ('6834', 'blu', 'blui')
            ]
        )

        # to insert one row and return the last inserted ID
        last_id = db.insert(
            'media',
            ('session_id', 'file_name', 'data_dir'),
            [
                ('6834', 'bla', 'bndjf')
            ],
            True
        ) # get_last_id is default to False in db.insert

        # to update data
        db.update(
            "UPDATE media SET file_name = %s WHERE ID = %s,
            ('filename.txt', '1')
        )

        db.disconnect()
    """

    def __init__(self, credentials, verbose):
        """
        Constructor method for the Database class.

        :param credentials: LORIS database credentials
         :type credentials: dict
        :param verbose    : whether to be verbose or not
         :type verbose    : bool
        """

        self.verbose = verbose

        # grep database credentials
        default_port   = 3306
        self.db_name   = credentials['database']
        self.user_name = credentials['username']
        self.password  = credentials['passwd']
        self.host_name = credentials['host']
        port           = credentials['port']

        if not self.user_name:
            raise Exception("\nUser name cannot be empty string.\n")
        if not self.db_name:
            raise Exception("\nDatabase name cannot be empty string.\n")
        if not self.host_name:
            raise Exception("\nDatabase host cannot be empty string.\n")

        self.port = int(port) if port else default_port

    def connect(self):
        """
        Attempts to connect to the database using the connection parameters
        passed at construction time. This method will throw a
        DatabaseException if the connection could not be established.
        """

        connect_statement = "\nConnecting to:" \
                            "\n\tdatabase: " + self.db_name   + \
                            "\n\tusername: " + self.user_name + \
                            "\n\thostname: " + self.host_name + \
                            "\n\tport    : " + str(self.port) + '\n'
        if self.verbose:
            print(connect_statement)

        try:
            self.con = MySQLdb.connect(
                host=self.host_name,
                user=self.user_name,
                passwd=self.password,
                port=self.port,
                db=self.db_name
            )
            #self.cnx.cursor = self.cnx.cursor(prepared=True)
        except MySQLdb.Error as err:
            raise Exception("Database connection failure: " + format(err))

    def pselect(self, query, args=None):
        """
        Executes a select query on the database. This method will first prepare
        the statement passed as parameter before sending the request to the
        database.

        :param query: select query to execute (containing the argument
                      placeholders if any
         :type query: str
        :param args: arguments to replace the placeholders with
         :type args: tuple

        :return: dictionary with MySQL column header name
         :rtype: dict
        """
        if self.verbose:
            print("\nExecuting query:\n\t" + query + "\n")
            if args:
                print("With arguments:\n\t"  + str(args) + "\n")

        try:
            cursor = self.con.cursor(MySQLdb.cursors.DictCursor)
            cursor.execute(query, args) if args else cursor.execute(query)
            results = cursor.fetchall()
            cursor.close()
        except MySQLdb.Error as err:
            raise Exception("Select query failure: " + format(err))

        return results

    def insert(self, table_name, column_names, values, get_last_id=False):
        """
        Inserts records in a given database table with the specified column
        values. This method will raise an exception if the record cannot be
        inserted.

        :param table_name  : name of the database table to insert into
         :type table_name  : str
        :param column_names: name of the table's columns to insert into
         :type column_names: tuple
        :param values      : list of values to insert into the table
         :type values      : list

        :return: the last ID that have been inserted into the database
         :rtype: int
        """

        placeholders = ','.join(map(lambda x: '%s', column_names))

        query = "INSERT INTO %s (%s) VALUES (%s)" % (
            table_name, ', '.join(column_names), placeholders
        )

        if self.verbose:
            print("\nExecuting query:\n\t" + query + "\n" \
                  "With arguments:\n\t" + str(values) + "\n")

        try:
            cursor = self.con.cursor()
            if isinstance(values, list):
                # if values is a list, use cursor.executemany
                # (to execute multiple inserts at once)
                cursor.executemany(query, values)
            else:
                # else, values is a tuple and want to execute only one insert
                cursor.execute(query, values)
            self.con.commit()
            last_id = cursor.lastrowid
            cursor.close()
        except MySQLdb.Error as err:
            raise Exception("Insert query failure: " + format(err))

        if get_last_id:
            return last_id

    def update(self, query, args):
        """
        Executes an update query on the database. This method will first prepare
        the statement passed as parameter before sending the request to the
        database.

        :param query: update query to be run
         :type query: str
        :param args : arguments to replace the placeholders with
         :type args : tuple
        """

        if self.verbose:
            print("\nExecuting query:\n\t" + query + "\n" \
                  + "With arguments:\n\t"  + str(args) + "\n")

        try:
            cursor = self.con.cursor()
            cursor.execute(query, args)
            self.con.commit()
        except MySQLdb.Error as err:
            raise Exception("Update query failure: " + format(err))

    def get_config(self, config_name):
        """
        Grep the Value of a ConfigSettings from the Config table.

        :param config_name: name of the ConfigSettings
         :type config_name: str

        :return: the value from the Config table or None if no value found
         :rtype: str
        """

        query = "SELECT Value FROM Config WHERE ConfigID = (" \
                  "SELECT ID FROM ConfigSettings WHERE Name = %s" \
                ");"
        config_value = self.pselect(query, (config_name,))

        return config_value[0]['Value'] if config_value else None

    def grep_id_from_lookup_table(self, id_field_name, table_name, where_field_name,
                                  where_value, insert_if_not_found=None):
        """
        Greps an ID from a given lookup table based on the provided value.

        :param id_field_name      : name of the ID field in the table
         :type id_field_name      : str
        :param table_name         : name of the lookup table
         :type table_name         : str
        :param where_field_name   : name of the field to use to find the ID
         :type where_field_name   : str
        :param where_value        : value of the field to use to find the ID
         :type where_value        : str
        :param insert_if_not_found: whether to insert a new row in the lookup table
                                    if no entry was found for the provided value
         :type insert_if_not_found: bool

        :return: ID found in the lookup table
         :rtype: int

        """

        query = "SELECT  " + id_field_name    + " " \
                "FROM    " + table_name       + " " \
                "WHERE   " + where_field_name + " = %s"

        result = self.pselect(query=query, args=(where_value,))
        id     = result[0][id_field_name] if result else None

        if not id and insert_if_not_found:
            id = self.insert(
                table_name   = table_name,
                column_names = (where_field_name,),
                values       = (where_value,),
                get_last_id  = True
            )

        if not id:
            message = "\nERROR: " + where_value + " " + where_field_name + \
                      " does not exist in " + table_name + "database table\n"
            print(message)
            sys.exit(lib.exitcode.SELECT_FAILURE)

        return id

    def disconnect(self):
        """
        Terminates the connection previously instantiated to the database if a
        connection was previously established.
        """

        if hasattr(self, 'cnx'):
            if self.verbose:
                print("\nDisconnecting from the database")

            try:
                self.con.close()
            except MySQLdb.Error as err:
                message = "Database disconnection failure: " + format(err)
                raise Exception(message)
