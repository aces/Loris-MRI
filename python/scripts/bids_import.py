#!/usr/bin/env python

"""Script to import BIDS structure into LORIS."""

import getopt
import json
import os
import re
import sys
from typing import Any, Literal

import lib.exitcode
import lib.physiological
import lib.utilities
from lib.bidsreader import BidsReader
from lib.candidate import Candidate
from lib.database import Database
from lib.database_lib.config import Config
from lib.eeg import Eeg
from lib.mri import Mri
from lib.session import Session

__license__ = "GPLv3"


sys.path.append('/home/user/python')


bids_eeg_modalities = ['eeg', 'ieeg']

bids_mri_modalities = ['anat', 'dwi', 'fmap', 'func']


# to limit the traceback when raising exceptions.
# sys.tracebacklimit = 0

def main():
    bids_dir         = ''
    verbose          = False
    createcand       = False
    createvisit      = False
    idsvalidation    = False
    nobidsvalidation = False
    type             = None
    profile          = ''
    nocopy           = False

    long_options = [
        "help",             "profile=",      "directory=",
        "createcandidate",  "createsession", "idsvalidation",
        "nobidsvalidation", "nocopy",        "type=",
        "verbose"
    ]
    usage        = (
        '\n'
        'usage  : bids_import -d <bids_directory> -p <profile> \n\n'
        'options: \n'
        '\t-p, --profile          : name of the python database config file in dicom-archive/.loris-mri\n'
        '\t-d, --directory        : BIDS directory to parse & insert into LORIS\n'
                                    'If directory is within $data_dir/assembly_bids, no copy will be performed'
        '\t-c, --createcandidate  : to create BIDS candidates in LORIS (optional)\n'
        '\t-s, --createsession    : to create BIDS sessions in LORIS (optional)\n'
        '\t-i, --idsvalidation    : to validate BIDS directory for a matching pscid/candid pair (optional)\n'
        '\t-b, --nobidsvalidation : to disable BIDS validation for BIDS compliance\n'
        '\t-a, --nocopy           : to disable dataset copy in data assembly_bids\n'
        '\t-t, --type             : raw | derivative. Specify the dataset type.'
                                    'If not set, the pipeline will look for both raw and derivative files.\n'
                                    'Required if no dataset_description.json is found.\n'
        '\t-v, --verbose          : be verbose\n'
    )

    try:
        opts, _ = getopt.getopt(sys.argv[1:], 'hp:d:csinat:v', long_options)
    except getopt.GetoptError:
        print(usage)
        sys.exit(lib.exitcode.GETOPT_FAILURE)

    for opt, arg in opts:
        if opt in ('-h', '--help'):
            print(usage)
            sys.exit()
        elif opt in ('-p', '--profile'):
            profile = os.environ['LORIS_CONFIG'] + "/.loris_mri/" + arg
        elif opt in ('-d', '--directory'):
            bids_dir = arg
        elif opt in ('-v', '--verbose'):
            verbose = True
        elif opt in ('-c', '--createcandidate'):
            createcand = True
        elif opt in ('-s', '--createsession'):
            createvisit = True
        elif opt in ('-i', '--idsvalidation'):
            idsvalidation = True
        elif opt in ('-n', '--nobidsvalidation'):
            nobidsvalidation = True
        elif opt in ('-a', '--nocopy'):
            nocopy = True
        elif opt in ('-t', '--type'):
            type = arg

    # input error checking and load config_file file
    config_file = input_error_checking(profile, bids_dir, usage)

    dataset_json = bids_dir + "/dataset_description.json"
    if not os.path.isfile(dataset_json) and not type:
        print('No dataset_description.json found. Please run with the --type option.')
        print(usage)
        sys.exit(lib.exitcode.MISSING_ARG)

    if type not in (None, 'raw', 'derivative'):
        print("--type must be one of 'raw', 'derivative'")
        print(usage)
        sys.exit(lib.exitcode.MISSING_ARG)

    # database connection
    db = Database(config_file.mysql, verbose)
    db.connect()

    config_obj = Config(db, verbose)
    data_dir   = config_obj.get_config('dataDirBasepath')
    # making sure that there is a final / in data_dir
    data_dir = data_dir if data_dir.endswith('/') else data_dir + "/"

    # read and insert BIDS data
    read_and_insert_bids(
        bids_dir,
        data_dir,
        verbose,
        createcand,
        createvisit,
        idsvalidation,
        nobidsvalidation,
        type,
        nocopy,
        db
    )


def input_error_checking(profile: str, bids_dir: str, usage: str) -> Any:
    """
    Checks whether the required inputs are set and that paths are valid. If
    the path to the config_file file valid, then it will import the file as a
    module so the database connection information can be used to connect.

    :param profile : path to the profile file with MySQL credentials
    :param bids_dir: path to the BIDS directory to parse and insert into LORIS
    :param usage   : script usage to be displayed when encountering an error

    :return: config_file module with database credentials (config_file.mysql)
    """

    if not profile:
        message = '\n\tERROR: you must specify a profile file using -p or ' \
                  '--profile option'
        print(message)
        print(usage)
        sys.exit(lib.exitcode.MISSING_ARG)

    if not bids_dir:
        message = '\n\tERROR: you must specify a BIDS directory using -d or ' \
                  '--directory option'
        print(message)
        print(usage)
        sys.exit(lib.exitcode.MISSING_ARG)

    if os.path.isfile(profile):
        sys.path.append(os.path.dirname(profile))
        config_file = __import__(os.path.basename(profile[:-3]))
    else:
        message = '\n\tERROR: you must specify a valid profile file.\n' + \
                  profile + ' does not exist!'
        print(message)
        print(usage)
        sys.exit(lib.exitcode.INVALID_PATH)

    if not os.path.isdir(bids_dir):
        message = '\n\tERROR: you must specify a valid BIDS directory.\n' + \
                  bids_dir + ' does not exist!'
        print(message)
        print(usage)
        sys.exit(lib.exitcode.INVALID_PATH)

    return config_file


def read_and_insert_bids(
    bids_dir: str, data_dir: str, verbose: bool, createcand: bool, createvisit: bool,
    idsvalidation: bool, nobidsvalidation: bool, type: Literal['raw', 'derivative'] | None, nocopy: bool, db: Database,
):
    """
    Read the provided BIDS structure and import it into the database.

    :param bids_dir         : path to the BIDS directory
    :param data_dir         : data_dir config value
    :param verbose          : flag for more printing if set
    :param createcand       : allow database candidate creation if it did not exist already
    :param createvisit      : allow database visit creation if it did not exist already
    :param idsvalidation    : allow pscid/candid validation in the BIDS directory name
    :param nobidsvalidation : disable bids dataset validation
    :param type             : Type of the dataset
    :param nocopy           : disable bids dataset copy in assembly_bids
    :param db               : db object
    """

    # grep config settings from the Config module
    config_obj      = Config(db, verbose)
    default_bids_vl = config_obj.get_config('default_bids_vl')

    # Validate that pscid and candid matches
    if idsvalidation:
        validateids(bids_dir, db, verbose)

    # load the BIDS directory
    if nobidsvalidation:
        bids_reader = BidsReader(bids_dir, verbose, False)
    else:
        bids_reader = BidsReader(bids_dir, verbose)
    if not bids_reader.participants_info          \
            or not bids_reader.cand_sessions_list \
            or not bids_reader.cand_session_modalities_list:
        message = '\n\tERROR: could not properly parse the following' \
                  'BIDS directory:' + bids_dir + '\n'
        print(message)
        sys.exit(lib.exitcode.UNREADABLE_FILE)

    loris_bids_root_dir = None
    if not nocopy:
        # create the LORIS_BIDS directory in data_dir based on Name and BIDS version
        loris_bids_root_dir = create_loris_bids_directory(
            bids_reader, data_dir, verbose
        )

    # Assumption all same project (for project-wide tags)
    single_project_id = None

    # loop through subjects
    for bids_subject_info in bids_reader.participants_info:

        # greps BIDS information for the candidate
        bids_id       = bids_subject_info['participant_id']
        bids_sessions = bids_reader.cand_sessions_list[bids_id]

        # greps BIDS candidate's info from LORIS (creates the candidate if it
        # does not exist yet in LORIS and the createcand flag is set to true)
        loris_cand_info = grep_or_create_candidate_db_info(
            bids_reader, bids_id, db, createcand, verbose
        )

        if not nocopy:
            # create the candidate's directory in the LORIS BIDS import directory
            lib.utilities.create_dir(loris_bids_root_dir + "sub-" + bids_id, verbose)

        cand_id    = loris_cand_info['CandID']
        center_id  = loris_cand_info['RegistrationCenterID']
        project_id = loris_cand_info['RegistrationProjectID']
        single_project_id = project_id

        cohort_id = None
        # TODO: change subproject -> cohort in participants.tsv?
        if 'subproject' in bids_subject_info:
            # TODO: change subproject -> cohort in participants.tsv?
            cohort = bids_subject_info['subproject']
            cohort_info = db.pselect(
                "SELECT CohortID FROM cohort WHERE title = %s",
                [cohort, ]
            )
            if len(cohort_info) > 0:
                cohort_id = cohort_info[0]['CohortID']

        # greps BIDS session's info for the candidate from LORIS (creates the
        # session if it does not exist yet in LORIS and the createvisit is set
        # to true. If no visit in BIDS structure, then use default visit_label
        # stored in the Config module)
        grep_candidate_sessions_info(
            bids_sessions, bids_id,    cand_id,       loris_bids_root_dir,
            createvisit,   verbose,    db,            default_bids_vl,
            center_id,     project_id, cohort_id,     nocopy
        )

    # Import root-level (dataset-wide) events.json
    # Assumption: Single project for project-wide tags
    bids_layout = bids_reader.bids_layout
    root_event_metadata_file = bids_layout.get_nearest(
        bids_dir,
        return_type='tuple',
        strict=False,
        extension='json',
        suffix='events',
        all_=False
    )

    dataset_tag_dict = {}
    if not root_event_metadata_file:
        message = '\nWARNING: no events metadata files (event.json) in ' \
                  'root directory'
        print(message)
    else:
        # copy the event file to the LORIS BIDS import directory
        copy_file = str.replace(
            root_event_metadata_file.path,
            bids_layout.root,
            ""
        )
        event_metadata_path = loris_bids_root_dir + copy_file.lstrip('/')
        lib.utilities.copy_file(root_event_metadata_file.path, event_metadata_path, verbose)

        # TODO: Move
        hed_query = 'SELECT * FROM hed_schema_nodes WHERE 1'
        hed_union = db.pselect(query=hed_query, args=())

        # load json data
        with open(root_event_metadata_file.path) as metadata_file:
            event_metadata = json.load(metadata_file)
        blake2 = lib.utilities.compute_blake2b_hash(root_event_metadata_file.path)
        physio = lib.physiological.Physiological(db, verbose)
        _, dataset_tag_dict = physio.insert_event_metadata(
            event_metadata=event_metadata,
            event_metadata_file=event_metadata_path,
            physiological_file_id=None,
            project_id=single_project_id,
            blake2=blake2,
            project_wide=True,
            hed_union=hed_union
        )

    # read list of modalities per session / candidate and register data
    for bids_sub_dir_info in bids_reader.cand_session_modalities_list:
        if bids_sub_dir_info.session_label is not None:
            visit_label = bids_sub_dir_info.session_label
        else:
            visit_label = default_bids_vl

        loris_bids_visit_rel_dir = os.path.join(
            f'sub-{bids_sub_dir_info.subject_label}',
            f'ses-{visit_label}',
        )

        for modality in bids_sub_dir_info.modalities:
            loris_bids_modality_rel_dir = loris_bids_visit_rel_dir + '/' + modality + '/'
            if not nocopy:
                lib.utilities.create_dir(loris_bids_root_dir + loris_bids_modality_rel_dir, verbose)

            if modality in bids_eeg_modalities:
                Eeg(
                    bids_reader   = bids_reader,
                    bids_sub_id   = bids_sub_dir_info.subject_label,
                    bids_ses_id   = bids_sub_dir_info.session_label,
                    bids_modality = modality,
                    db            = db,
                    verbose       = verbose,
                    data_dir      = data_dir,
                    default_visit_label    = default_bids_vl,
                    loris_bids_eeg_rel_dir = loris_bids_modality_rel_dir,
                    loris_bids_root_dir    = loris_bids_root_dir,
                    dataset_tag_dict       = dataset_tag_dict,
                    dataset_type           = type
                )

            elif modality in bids_mri_modalities:
                Mri(
                    bids_reader   = bids_reader,
                    bids_sub_id   = bids_sub_dir_info.subject_label,
                    bids_ses_id   = bids_sub_dir_info.session_label,
                    bids_modality = modality,
                    db            = db,
                    verbose       = verbose,
                    data_dir      = data_dir,
                    default_visit_label    = default_bids_vl,
                    loris_bids_mri_rel_dir = loris_bids_modality_rel_dir,
                    loris_bids_root_dir    = loris_bids_root_dir
                )

    # disconnect from the database
    db.disconnect()


def validateids(bids_dir: str, db: Database, verbose: bool):
    """
    Validate that pscid and candid matches

    :param bids_dir : path to the BIDS directory
    :param db       : database handler object
    :param verbose  : flag for more printing if set
    """

    bids_folder = bids_dir.rstrip('/').split('/')[-1]
    bids_folder_parts = bids_folder.split('_')
    psc_id = bids_folder_parts[0]
    cand_id = bids_folder_parts[1]

    candidate = Candidate(verbose, cand_id=cand_id)
    loris_cand_info = candidate.get_candidate_info_from_loris(db)

    if not loris_cand_info:
        print("ERROR: could not find a candidate with cand_id " + cand_id + ".")
        sys.exit(lib.exitcode.CANDID_NOT_FOUND)
    if loris_cand_info['PSCID'] != psc_id:
        print("ERROR: cand_id " + cand_id + " and psc_id " + psc_id + " do not match.")
        sys.exit(lib.exitcode.CANDIDATE_MISMATCH)


def create_loris_bids_directory(bids_reader: BidsReader, data_dir: str, verbose: bool) -> str:
    """
    Creates the LORIS BIDS import root directory (with name and BIDS version)
    and copy over the dataset_description.json, README and participants.tsv
    files.

    :param bids_reader : BIDS information handler object
    :param data_dir    : path of the LORIS data directory
    :param verbose     : if true, prints out information while executing

    :return: path to the LORIS BIDS import root directory
    """

    # making sure that there is a final / in bids_dir
    bids_dir = bids_reader.bids_dir
    bids_dir = bids_dir if bids_dir.endswith('/') else bids_dir + "/"

    # determine the root directory of the LORIS BIDS and create it if does not exist
    name = re.sub("[^0-9a-zA-Z]+", "_", bids_reader.dataset_name)  # get name of the dataset
    version = re.sub(r"[^0-9a-zA-Z\.]+", "_", bids_reader.bids_version)  # get BIDSVersion of the dataset

    # the LORIS BIDS directory will be in data_dir/BIDS/ and named with the
    # concatenation of the dataset name and the BIDS version
    loris_bids_dirname = lib.utilities.create_dir(
        data_dir + "bids_imports/" + name + "_BIDSVersion_" + version + "/",
        verbose
    )

    # copy the dataset JSON file to the new directory
    lib.utilities.copy_file(
        bids_dir + "dataset_description.json",
        loris_bids_dirname + "dataset_description.json",
        verbose
    )

    # copy the README file to the new directory
    if os.path.isfile(bids_dir + "README"):
        lib.utilities.copy_file(
            bids_dir + "README",
            loris_bids_dirname + "README",
            verbose
        )

    # copy the participant.tsv file to the new directory
    if os.path.exists(loris_bids_dirname + "participants.tsv"):
        lib.utilities.append_to_tsv_file(
            bids_dir + "participants.tsv",
            loris_bids_dirname + "participants.tsv",
            "participant_id",
            verbose
        )
    else:
        lib.utilities.copy_file(
            bids_dir + "participants.tsv",
            loris_bids_dirname + "participants.tsv",
            verbose
        )

    return loris_bids_dirname


def grep_or_create_candidate_db_info(
    bids_reader: BidsReader, bids_id: str, db: Database, createcand: bool, verbose: bool
) -> dict[str, Any]:
    """
    Greps (or creates if candidate does not exist and createcand is true) the
    BIDS candidate in the LORIS candidate's table and return a list of
    candidates with their related fields from the database.

    :param bids_reader   : BIDS information handler object
    :param bids_id       : bids_id to be used (CandID or PSCID)
    :param db            : database handler object
    :param createcand    : if true, creates the candidate in LORIS
    :param verbose       : if true, prints out information while executing

    :return: The dictionary of the candidate database record
    """

    candidate = Candidate(verbose=verbose, cand_id=bids_id)
    loris_cand_info = candidate.get_candidate_info_from_loris(db)

    if not loris_cand_info:
        candidate = Candidate(verbose, psc_id=bids_id)
        loris_cand_info = candidate.get_candidate_info_from_loris(db)

    if not loris_cand_info and createcand:
        loris_cand_info = candidate.create_candidate(
            db, bids_reader.participants_info
        )
        if not loris_cand_info:
            print("Creating candidate failed. Cannot importing the files.\n")
            sys.exit(lib.exitcode.CANDIDATE_CREATION_FAILURE)

    if not loris_cand_info:
        print("Candidate " + bids_id + " not found. You can retry with the --createcandidate option.\n")
        sys.exit(lib.exitcode.CANDIDATE_NOT_FOUND)

    return loris_cand_info


def grep_or_create_session_db_info(
        bids_id: str, cand_id: int, visit_label: str, db: Database, createvisit: bool, verbose: bool,
        loris_bids_dir: str, center_id: int, project_id: int, cohort_id: int, nocopy: bool
) -> dict[str, Any]:
    """
    Greps (or creates if session does not exist and createvisit is true) the
    BIDS session in the LORIS session's table and return a list of
    sessions with their related fields from the database.

    :parma bids_id        : BIDS ID of the session
    :param cand_id        : CandID to use to create the session
    :param visit_label    : Visit label to use to create the session
    :param db             : database handler object
    :param createvisit    : if true, creates the session in LORIS
    :param verbose        : if true, prints out information while executing
    :param loris_bids_dir : LORIS BIDS import root directory to copy data
    :param center_id      : CenterID  to use to create the session
    :param project_id     : ProjectID  to use to create the session
    :param cohort_id      : CohortID to use to create the session
    :param nocopy         : if true, skip the assembly_bids dataset copy

    :return: session information grepped from LORIS for cand_id and visit_label
    """

    session = Session(db, verbose, cand_id, visit_label, center_id, project_id, cohort_id)
    loris_vl_info = session.get_session_info_from_loris()

    if not loris_vl_info and createvisit:
        loris_vl_info = session.create_session()

    if not nocopy:
        # create the visit directory for in the candidate folder of the LORIS
        # BIDS import directory
        lib.utilities.create_dir(
            loris_bids_dir + "sub-" + bids_id + "/ses-" + visit_label,
            verbose
        )

    return loris_vl_info


def grep_candidate_sessions_info(
    bids_ses: list[str], bids_id: str, cand_id: int, loris_bids_dir: str, createvisit: bool, verbose: bool,
    db: Database, default_vl: str, center_id: int, project_id: int, cohort_id: int, nocopy: bool,
) -> list[dict[str, Any]]:
    """
    Greps all session info dictionaries for a given candidate and aggregates
    them into a list, with one entry per session. If the session does not
    exist in LORIS and that createvisit is true, it will create the session
    first.

    :param bids_ses       : list of BIDS sessions to grep info or insert
    :param bids_id        : BIDS ID of the candidate
    :param cand_id        : candidate's CandID
    :param loris_bids_dir : LORIS BIDS import root directory to copy data
    :param createvisit    : if true, creates the visits in LORIS
    :param verbose        : if true, prints out information while executing
    :param db             : database handler object
    :param default_vl     : default visit label from the Config module
    :param center_id      : center ID associated to the candidate and visit
    :param project_id     : project ID associated to the candidate and visit
    :param cohort_id      : cohort ID associated to the candidate and visit
    :param nocopy         : if true, skip the assembly_bids dataset copy

    :return: list of all session's dictionaries for a given candidate
    """

    loris_sessions_info = []

    if not bids_ses:
        loris_ses_info = grep_or_create_session_db_info(
            bids_id,     cand_id,    default_vl,     db,
            createvisit, verbose,    loris_bids_dir,
            center_id,   project_id, cohort_id,      nocopy
        )
        loris_sessions_info.append(loris_ses_info)
    else:
        for visit_label in bids_ses:
            loris_ses_info = grep_or_create_session_db_info(
                bids_id,     cand_id,    visit_label,    db,
                createvisit, verbose,    loris_bids_dir,
                center_id,   project_id, cohort_id,      nocopy
            )
            loris_sessions_info.append(loris_ses_info)

    return loris_sessions_info


if __name__ == "__main__":
    main()
