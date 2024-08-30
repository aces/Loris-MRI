"""Reads a BIDS structure into a data dictionary using bids.grabbids."""

import re
import sys
import json

import lib.exitcode
import lib.utilities as utilities

try:
    from bids import BIDSLayout
except ImportError:
    try:
        from bids.grabbids import BIDSLayout
    except ImportError:
        print("Could not find bids.layout or bids.grabbids")
        exit(lib.exitcode.INVALID_IMPORT)

# import bids
# BIDSLayoutIndexer is required for PyBIDS >= 0.12.1
# bids_pack_version = list(map(int, bids.__version__.split('.')))
# if (bids_pack_version[0] > 0
#     or bids_pack_version[1] > 12
#    or (bids_pack_version[1] == 12 and bids_pack_version[2] > 0)):

# from bids import BIDSLayoutIndexer

__license__ = "GPLv3"


class BidsReader:
    """
    This class reads a BIDS structure into a data dictionary using BIDS grabbids.
    This dictionary will then be used to determine what to register into the
    database.

    :Example:

        from lib.bidsreader import BidsReader

        # load the BIDS directory
        bids_reader = BidsReader(bids_dir)
    """

    def __init__(self, bids_dir, verbose, validate = True):
        """
        Constructor method for the BidsReader class.

        :param bids_dir: path to the BIDS structure to read
         :type bids_dir: str
        :param verbose : boolean to print verbose information
         :type verbose : bool
        :param validate : boolean to validate the BIDS dataset
         :type validate : bool
        """

        self.verbose     = verbose
        self.bids_dir    = bids_dir
        self.bids_layout = self.load_bids_data(validate)

        # load dataset name and BIDS version
        self.dataset_name = None
        self.bids_version = None
        try:
            dataset_json = bids_dir + "/dataset_description.json"
            dataset_description = {}
            with open(dataset_json) as json_file:
                dataset_description = json.load(json_file)
            self.dataset_name = dataset_description['Name']
            self.bids_version = dataset_description['BIDSVersion']
        except Exception:
            print("WARNING: Cannot read dataset_description.json")

        # load BIDS candidates information
        self.participants_info = self.load_candidates_from_bids()

        # load BIDS sessions information
        self.cand_sessions_list = self.load_sessions_from_bids()

        # load BIDS modality information
        self.cand_session_modalities_list = self.load_modalities_from_bids()

    def load_bids_data(self, validate):
        """
        Loads the BIDS study using the BIDSLayout function (part of the pybids
        package) and return the object.

        :return: bids structure
        """

        if self.verbose:
            print('Loading the BIDS dataset with BIDS layout library...\n')

        exclude_arr   = ['/code/', '/sourcedata/', '/log/', '.git/']
        force_arr     = [re.compile(r"_annotations\.(tsv|json)$")]

        # BIDSLayoutIndexer is required for PyBIDS >= 0.12.1
        # bids_pack_version = list(map(int, bids.__version__.split('.')))
        # disabled until is a workaround for https://github.com/bids-standard/pybids/issues/760 is found
        # [file] bids_import.py
        # [function] read_and_insert_bids
        # [line] for modality in row['modalities']: (row['modalities'] is empty)
        # if (bids_pack_version[0] > 0
        #    or bids_pack_version[1] > 12
        #    or (bids_pack_version[1] == 12 and bids_pack_version[2] > 0)):
        #    bids_layout = BIDSLayout(
        #        root=self.bids_dir,
        #        indexer=BIDSLayoutIndexer(ignore=exclude_arr, force_index=force_arr)
        #    )
        # else:
        bids_layout = BIDSLayout(
            root=self.bids_dir,
            ignore=exclude_arr,
            force_index=force_arr,
            derivatives=True,
            validate=validate
        )

        if self.verbose:
            print('\t=> BIDS dataset loaded with BIDS layout\n')

        return bids_layout

    def load_candidates_from_bids(self):
        """
        Loads the list of candidates from the BIDS study. List of
        participants and their information will be stored in participants_info.

        :return: list of dictionaries with participant information from BIDS
         :rtype: list
        """

        if self.verbose:
            print('Grepping candidates from the BIDS layout...')

        # grep the participant.tsv file and parse it
        participants_info = None
        for file in self.bids_layout.get(suffix='participants', return_type='filename'):
            # note file[0] returns the path to participants.tsv
            if 'participants.tsv' in file:
                participants_info = utilities.read_tsv_file(file)
            else:
                continue

        if participants_info:
            self.candidates_list_validation(participants_info)
        else:
            bids_subjects = self.bids_layout.get_subjects()
            participants_info = [{'participant_id': sub_id} for sub_id in bids_subjects]

        if self.verbose:
            print('\t=> List of participants found:')
            for participant in participants_info:
                print('\t\t' + participant['participant_id'])
            print('\n')

        return participants_info

    def candidates_list_validation(self, participants_info):
        """
        Validates whether the subjects listed in participants.tsv match the
        list of participant directory. If there is a mismatch, will exit with
        error code from lib.exitcode.
        """

        if self.verbose:
            print('Validating the list of participants...')

        subjects = self.bids_layout.get_subjects()

        mismatch_message = ("\nERROR: Participant ID mismatch between "
                            "participants.tsv and raw data found in the BIDS "
                            "directory")

        # check that all subjects listed in participants_info are also in
        # subjects array and vice versa
        for row in participants_info:
            # remove the "sub-" in front of the subject ID if present
            row['participant_id'] = row['participant_id'].replace('sub-', '')
            if not row['participant_id'] in subjects:
                print(mismatch_message)
                print(row['participant_id'] + 'is missing from the BIDS Layout')
                print('List of subjects parsed by the BIDS layout: ' + ', '.join(subjects))
                sys.exit(lib.exitcode.BIDS_CANDIDATE_MISMATCH)
            # remove the subject from the list of subjects
            subjects.remove(row['participant_id'])

        # check that no subjects are left in subjects array
        if subjects:
            print(mismatch_message)
            sys.exit(lib.exitcode.BIDS_CANDIDATE_MISMATCH)

        if self.verbose:
            print('\t=> Passed validation of the list of participants\n')

    def load_sessions_from_bids(self):
        """
        Grep the list of sessions for each candidate directly from the BIDS
        structure.

        :return: dictionary with the list of sessions and candidates found in the
                 BIDS structure
         :rtype: dict
        """

        if self.verbose:
            print('Grepping list of sessions from the BIDS layout...')

        cand_sessions = {}

        for row in self.participants_info:
            ses = self.bids_layout.get_sessions(subject=row['participant_id'])
            cand_sessions[row['participant_id']] = ses

        if self.verbose:
            print('\t=> List of sessions found:\n')
            for candidate in cand_sessions:
                if cand_sessions[candidate]:
                    print('\t\t' + candidate + ': ' + ', '.join(cand_sessions[candidate]))
                else:
                    print('\t\tNo session found for candidate ' + candidate)
            print('\n')

        return cand_sessions

    def load_modalities_from_bids(self):
        """
        Grep the list of modalities available for each session and candidate directly
        from the BIDS structure.

        :return: dictionary for candidate and session with list of modalities
         :rtype: dict
        """

        if self.verbose:
            print('Grepping the different modalities from the BIDS layout...')

        cand_session_modalities_list = []

        for subject, visit_list in self.cand_sessions_list.items():
            if visit_list:
                for visit in visit_list:
                    modalities = self.bids_layout.get_datatype(subject=subject, session=visit)
                    cand_session_modalities_list.append({
                        'bids_sub_id': subject,
                        'bids_ses_id': visit,
                        'modalities' : modalities
                    })
            else:
                modalities = self.bids_layout.get_datatype(subject=subject)
                cand_session_modalities_list.append({
                    'bids_sub_id': subject,
                    'bids_ses_id': None,
                    'modalities' : modalities
                })

        if self.verbose:
            print('\t=> Done grepping the different modalities from the BIDS layout\n')

        return cand_session_modalities_list

    @staticmethod
    def grep_file(files_list, match_pattern, derivative_pattern=None):
        """
        Grep a unique file based on a match pattern and returns it.

        :param files_list        : list of files to look into
         :type files_list        : list
        :param match_pattern     : pattern to use to find the file
         :type match_pattern     : str
        :param derivative_pattern: derivative pattern to use if the file we look for
                                   is a derivative file
         :type derivative_pattern: str

        :return: name of the first file that matches the pattern
         :rtype: str
        """

        for filename in files_list:
            if not derivative_pattern:
                if 'derivatives' in filename:
                    # skip all files with 'derivatives' string in their path
                    continue
                elif re.search(match_pattern, filename):
                    # grep the file that matches the match_pattern (extension)
                    return filename
            else:
                matches_derivative = re.search(derivative_pattern, filename)
                if re.search(match_pattern, filename) and matches_derivative:
                    return filename

        return None
