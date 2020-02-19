"""This class performs DICOM archive related database queries and common checks"""

import lib.exitcode
import lib.utilities as utilities
from lib.candidate import Candidate
from lib.database_lib.site import Site


__license__ = "GPLv3"


class Tarchive:
    """
    This class performs database queries for imaging dataset (MRI, PET...).

    :Example:

        from lib.tarchive  import Tarchive
        from lib.database import Database

        # database connection
        db = Database(config.mysql, verbose)
        db.connect()

        tarchive = Tarchive(db, verbose)

        ...
    """

    def __init__(self, db, verbose, config_file=None):
        """
        Constructor method for the Tarchive class.

        :param db     : Database class object
         :type db     : object
        :param verbose: whether to be verbose
         :type verbose: bool
        :param config_file: config file with custom functions
         :type config_file: str
        """

        self.db          = db
        self.verbose     = verbose
        self.config_file = config_file

        # this will contain the tarchive info
        self.tarchive_info_dict = dict()

    def create_tarchive_dict(self, archive_location=None, tarchive_id=None):
        """
        Create dictionary with DICOM archive information selected from the tarchive table.

        :param archive_location: relative location of the DICOM archive (without data directory path)
         :type archive_location: str
        :param tarchive_id     : TarchiveID of the DICOM archive in the tarchive table
         :type tarchive_id     : int

        :return: dictionary with the DICOM archive information selected from the tarchive table
         :rtype: dict
        """

        query = 'SELECT * FROM tarchive WHERE '
        args = None

        if archive_location:
            query += ' ArchiveLocation LIKE %s '
            args = ('%' + archive_location + '%',)
        elif tarchive_id:
            query += ' TarchiveID = %s '
            args = (tarchive_id,)

        results = self.db.pselect(query=query, args=args)

        # save the result in self.tarchive_info_dict and return True if a row was found
        # return False if no row found for the archive location or tarchiveID in the tarchive table
        if results:
            self.tarchive_info_dict = results[0]
            return True
        else:
            return False

    def validate_dicom_archive_md5sum(self, tarchive_path):
        """
        This function validates that the md5sum of the DICOM archive on the filesystem is the same
        as the md5sum of the registered entry in the tarchive table.

        :param tarchive_path: path to the DICOM archive to be validated against the database
         :type tarchive_path: str

        :return result: dictionary with the result of the validation
         :rtype result: dict

        """

        # compute the md5sum of the tarchive file
        tarchive_file_md5sum = utilities.compute_md5sum(tarchive_path)

        # grep the md5sum stored in the database
        tarchive_db_md5sum = self.tarchive_info_dict['md5sumArchive'].split()[0]

        # check that the two md5sum are the same
        result = dict()
        if tarchive_db_md5sum == tarchive_file_md5sum:
            result['success'] = True
            result['message'] = '-> checksum for target   : ' + tarchive_file_md5sum + '\n' \
                                '-> checksum from database: ' + tarchive_db_md5sum
        else:
            result['success'] = False
            result['message'] = 'ERROR: DICOM archive seems corrupted or modified. ' \
                                'Upload will exit now.'

        return result
