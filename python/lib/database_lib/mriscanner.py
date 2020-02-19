"""This class performs database queries for the mri_scanner table"""


__license__ = "GPLv3"


class MriScanner:

    def __init__(self, db, verbose):
        """
        Constructor method for the MriScanner class.

        :param db     : Database class object
         :type db     : object
        :param verbose: whether to be verbose
         :type verbose: bool
        """

        self.db      = db
        self.verbose = verbose

    def determine_scanner_information(self, tarchive_info_dict, site_dict):
        """
        Select a ScannerID based on the scanner information gathered from the headers of the
        DICOM archive. If a ScannerID is not found for the scanner but register_new_scanner
        is set to True in the Config table, a new entry will be inserted into the mri_scanner table.

        :param tarchive_info_dict  : dictionary with information about the DICOM archive queried
                                     from the tarchive table
         :type tarchive_info_dict  : dict
        :param site_dict           : dictionary with the site information
         :type site_dict           : dict

        :return: dictionary with ScannerID information
         :rtype: dict
        """

        query = 'SELECT ID AS ScannerID '   \
                ' FROM mri_scanner '        \
                ' WHERE Manufacturer = %s ' \
                '   AND Software = %s '     \
                '   AND Serial_number =%s ' \
                '   AND Model = %s '

        manufacturer     = tarchive_info_dict['ScannerManufacturer']
        software_version = tarchive_info_dict['ScannerSoftwareVersion']
        serial_number    = tarchive_info_dict['ScannerSerialNumber']
        model            = tarchive_info_dict['ScannerModel']
        arguments        = (manufacturer, software_version, serial_number, model)

        results = self.db.pselect(query=query, args=arguments)
        if results:
            return results[0]

        # if could not find a scanner ID, register a new scanner in mri_scanner
        scanner_id = self.register_new_scanner(tarchive_info_dict, site_dict['CenterID'])
        return {'ScannerID': scanner_id}

    def register_new_scanner(self, tarchive_info_dict, center_id):
        """
        Inserts a new entry in the mri_scanner table after having created a new candidate to
        associate to that scanner.

        :param tarchive_info_dict: dictionary with information about the DICOM archive queried
                                   from the tarchive table
         :type tarchive_info_dict: dict
        :param center_id         : CenterID of the center associated to that scanner
         :type center_id         : int

        :return scanner_id: ScannerID of the new entry in the mri_scanner table
         :rtype scanner_id: int
        """

        # create a new candidate for the scanner
        candidate    = Candidate(self.verbose)
        new_cand_id  = candidate.generate_cand_id(self.db)
        column_names = (
            'CandID', 'PSCID',       'RegistrationCenterID', 'Date_active',
            'UserID', 'Entity_type', 'Date_registered',
        )
        values = (
            new_cand_id,  'scanner', center_id,              datetime.datetime.now(),
            'imaging.py', 'Scanner', datetime.datetime.now()
        )
        self.db.insert(
            table_name   = 'candidate',
            column_names = column_names,
            values       = values
        )

        # create the new scanner ID
        manufacturer  = tarchive_info_dict['ScannerManufacturer'],
        serial_number = tarchive_info_dict['ScannerSerialNumber'],
        software      = tarchive_info_dict['ScannerSoftwareVersion'],
        model         = tarchive_info_dict['ScannerModel'],
        scanner_id = self.db.insert(
            table_name   = 'mri_scanner',
            column_names = ('Manufacturer', 'Model', 'Serial_number', 'Software', 'CandID'),
            values       = (manufacturer,   model,   serial_number,   software,   new_cand_id),
            get_last_id  = True
        )

        return scanner_id
