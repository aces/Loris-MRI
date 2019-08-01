"""Deals with sub-XXX_scans.tsv BIDS files"""

import os
from dateutil.parser import parse

import lib.utilities as utilities


__license__ = "GPLv3"


class ScansTSV:
    """
    This class reads the BIDS sub-XXX_scans.tsv file that includes acquisition level information
    such as scan date or age at scan...

    :Example:
        from lib.scanstsv import ScansTSV

        scan_info = ScansTSV(scans_tsv_file, acquisition_file)

        acquisition_time = scan_info.get_acquisition_time()
        age_at_scan      = scan_info.get_age_at_scan

    """

    def __init__(self, scans_tsv_file, acquisition_file, verbose):
        """
        Constructor method for the ScansTSV class

        :param scans_tsv_file  : path to the BIDS sub-XXX_scans.tsv file
         :type scans_tsv_file  : str
        :param acquisition_file: path to the acquisition file (.nii, .set, .edf...)
         :type acquisition_file: str
        """

        self.verbose = verbose

        # store files' paths
        self.scans_tsv_file   = scans_tsv_file
        self.acquisition_file = acquisition_file

        # read the TSV file and store the header names and data
        self.tsv_entries = utilities.read_tsv_file(self.scans_tsv_file)
        self.tsv_headers = self.tsv_entries[0]

        # get the acquisition information for the acquisition file
        self.acquisition_data = self.find_acquisition_data()

    def find_acquisition_data(self):
        """
        Gets the information for the acquisition file from the TSV file.

        :return: the acquisition information found in the TSV file for the acquisition file
         :rtype: list
        """

        for entry in self.tsv_entries:
            if os.path.basename(self.acquisition_file) in entry['filename']:
                return entry

    def get_acquisition_time(self):
        """
        Get the acquisition time of the acquisition file.

        :return: acquisition time or None if not found
         :rtype: str
        """

        if 'acq_time' in self.tsv_headers:
            eeg_acq_time = self.tsv_entries['acq_time']
            try:
                eeg_acq_time = parse(eeg_acq_time)
            except ValueError as e:
                message = "ERROR: could not convert acquisition time '" + \
                          eeg_acq_time + \
                          "' to datetime: " + str(e)
                print(message)
                exit(lib.exitcode.PROGRAM_EXECUTION_FAILURE)
            return eeg_acq_time

        return None

    def get_age_at_scan(self):
        """
        Get the age at the time of acquisition.

        :return: age at acquisition time
         :rtype: str
        """

        # list of possible header names containing the age information
        age_header_list = ['age', 'age_at_scan', 'age_acq_time']

        for header_name in age_header_list:
            if header_name in self.tsv_headers:
                return self.acquisition_data[header_name].strip()

        return None

    def copy_scans_tsv_file_to_loris_bids_dir(self, bids_sub_id, loris_bids_root_dir, data_dir):

        file = self.scans_tsv_file
        copy = loris_bids_root_dir + '/sub-' + bids_sub_id + '/' + os.path.basename(self.scans_tsv_file)
        utilities.copy_file(file, copy, self.verbose)

        # determine the relative path and return it
        relative_path = copy.replace(data_dir, "")

        return relative_path
