#!/usr/bin/env python

"""Script to import BIDS structure into LORIS."""

import getopt
import json
import os
import re
import sys
from pathlib import Path

from loris_bids_reader.files.participants import BidsParticipantsTsvFile
from loris_bids_reader.mri.reader import BidsMriDataTypeReader
from loris_bids_reader.reader import BidsDatasetReader
from loris_utils.crypto import compute_file_blake2b_hash

import lib.exitcode
import lib.physiological
import lib.utilities
from lib.candidate import Candidate
from lib.config import get_default_bids_visit_label_config
from lib.config_file import load_config
from lib.database import Database
from lib.database_lib.config import Config
from lib.db.queries.candidate import try_get_candidate_with_cand_id, try_get_candidate_with_psc_id
from lib.db.queries.session import try_get_session_with_cand_id_visit_label
from lib.eeg import Eeg
from lib.env import Env
from lib.import_bids_dataset.check_sessions import check_or_create_bids_sessions
from lib.import_bids_dataset.check_subjects import check_or_create_bids_subjects
from lib.import_bids_dataset.env import BidsImportEnv
from lib.import_bids_dataset.mri import import_bids_mri_acquisition
from lib.make_env import make_env


def main():
    bids_dir         = ''
    verbose          = False
    createcand       = False
    createvisit      = False
    idsvalidation    = False
    nobidsvalidation = False
    type             = None
    profile          = None
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
        '\t-p, --profile          : name of the python database config file in the config directory\n'
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
            profile = arg
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
    config_file = load_config(profile)
    input_error_checking(bids_dir, usage)
    tmp_dir_path = lib.utilities.create_processing_tmp_dir('mass_nifti_pic')
    env = make_env('bids_import', {}, config_file, tmp_dir_path, verbose)

    dataset_json = bids_dir + "/dataset_description.json"
    if not os.path.isfile(dataset_json) and not type:
        print('No dataset_description.json found. Please run with the --type option.')
        print(usage)
        sys.exit(lib.exitcode.MISSING_ARG)

    if type and type not in ('raw', 'derivative'):
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
        env,
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


def input_error_checking(bids_dir, usage):
    """
    Checks whether the required inputs are set and that paths are valid.

    :param bids_dir: path to the BIDS directory to parse and insert into LORIS
     :type bids_dir: str
    :param usage   : script usage to be displayed when encountering an error
     :type usage   : st
    """

    if not bids_dir:
        message = '\n\tERROR: you must specify a BIDS directory using -d or ' \
                  '--directory option'
        print(message)
        print(usage)
        sys.exit(lib.exitcode.MISSING_ARG)

    if not os.path.isdir(bids_dir):
        message = '\n\tERROR: you must specify a valid BIDS directory.\n' + \
                  bids_dir + ' does not exist!'
        print(message)
        print(usage)
        sys.exit(lib.exitcode.INVALID_PATH)


def read_and_insert_bids(
    env: Env, bids_dir,      data_dir,      verbose, createcand, createvisit,
    idsvalidation, nobidsvalidation, type,    nocopy,  db
):
    """
    Read the provided BIDS structure and import it into the database.

    :param bids_dir         : path to the BIDS directory
     :type bids_dir         : str
    :param data_dir         : data_dir config value
     :type data_dir         : string
    :param verbose          : flag for more printing if set
     :type verbose          : bool
    :param createcand       : allow database candidate creation if it did not exist already
     :type createcand       : bool
    :param createvisit      : allow database visit creation if it did not exist already
     :type createvisit      : bool
    :param idsvalidation    : allow pscid/candid validation in the BIDS directory name
     :type idsvalidation    : bool
    :param nobidsvalidation : disable bids dataset validation
     :type nobidsvalidation : bool
    :param type             : raw | derivative. Type of the dataset
     :type type             : string
    :param nocopy           : disable bids dataset copy in assembly_bids
     :type nocopy           : bool
    :param db               : db object
     :type db               : object

    """

    # grep config settings from the Config module
    default_bids_vl = get_default_bids_visit_label_config(env)

    # Validate that pscid and candid matches
    if idsvalidation:
        validateids(bids_dir, db, verbose)

    # load the BIDS directory
    bids_reader = BidsDatasetReader(Path(bids_dir), not nobidsvalidation)

    if bids_reader.data_types == []:
        print(f"Could not read the BIDS directory '{bids_dir}'.")
        sys.exit(lib.exitcode.UNREADABLE_FILE)

    print("List of subjects found in the BIDS dataset:")
    for subject_label in bids_reader.subject_labels:
        print(f"- {subject_label}")

    print("List of sessions found in the BIDS dataset:")
    for session_label in bids_reader.session_labels:
        print(f"- {session_label}")

    if bids_reader.participants_file is not None:
        validate_participants(bids_reader, bids_reader.participants_file)

    loris_bids_root_dir = None
    if not nocopy:
        # create the LORIS_BIDS directory in data_dir based on Name and BIDS version
        loris_bids_root_dir = create_loris_bids_directory(
            bids_reader, data_dir, verbose
        )

    check_or_create_bids_subjects(
        env,
        [subject.info for subject in bids_reader.subjects],
        createcand,
    )

    sessions = check_or_create_bids_sessions(
        env,
        [session.info for session in bids_reader.sessions],
        createvisit,
    )

    env.db.commit()

    # Assumption all same project (for project-wide tags)
    single_project_id = sessions[0].project.id

    # Import root-level (dataset-wide) events.json
    # Assumption: Single project for project-wide tags
    bids_layout = bids_reader.layout
    root_event_metadata_file = bids_layout.get_nearest(
        bids_dir,
        return_type='tuple',
        strict=False,
        extension='json',
        suffix='events',
        all_=False,
        subject=None,
        session=None
    )

    dataset_tag_dict = {}
    if not root_event_metadata_file:
        message = '\nWARNING: no events metadata files (events.json) in ' \
                  'root directory'
        print(message)
    else:
        # copy the event file to the LORIS BIDS import directory
        copy_file = str.replace(
            root_event_metadata_file.path,
            bids_layout.root,
            ""
        ).lstrip('/')

        if not nocopy:
            event_metadata_path = loris_bids_root_dir + copy_file
            lib.utilities.copy_file(root_event_metadata_file.path, event_metadata_path, verbose)

        # TODO: Move
        hed_query = 'SELECT * FROM hed_schema_nodes WHERE 1'
        hed_union = db.pselect(query=hed_query, args=())

        # load json data
        with open(root_event_metadata_file.path) as metadata_file:
            event_metadata = json.load(metadata_file)
        blake2 = compute_file_blake2b_hash(root_event_metadata_file.path)
        physio = lib.physiological.Physiological(env, db, verbose)
        _, dataset_tag_dict = physio.insert_event_metadata(
            event_metadata=event_metadata,
            event_metadata_file=event_metadata_path,
            physiological_file=None,
            project_id=single_project_id,
            blake2=blake2,
            project_wide=True,
            hed_union=hed_union
        )

    import_env = BidsImportEnv(
        data_dir_path    = Path(data_dir),
        source_bids_path = Path(bids_dir),
        loris_bids_path  = Path(loris_bids_root_dir).relative_to(data_dir) if loris_bids_root_dir is not None else None,
    )

    # read list of modalities per session / candidate and register data
    for data_type_reader in bids_reader.data_types:
        bids_info = data_type_reader.info
        visit_label = bids_info.session if bids_info.session is not None else default_bids_vl
        loris_bids_data_type_rel_dir = os.path.join(
            f'sub-{bids_info.subject}',
            f'ses-{visit_label}',
            bids_info.data_type,
        )

        if not nocopy:
            lib.utilities.create_dir(os.path.join(loris_bids_root_dir, loris_bids_data_type_rel_dir), verbose)

        candidate = try_get_candidate_with_cand_id(env.db, bids_info.subject)
        if candidate is None:
            candidate = try_get_candidate_with_psc_id(env.db, bids_info.subject)

        session = try_get_session_with_cand_id_visit_label(env.db, candidate.cand_id, visit_label)

        match (data_type_reader, bids_info.data_type):
            case (_, 'eeg' | 'ieeg'):
                Eeg(
                    env,
                    import_env,
                    bids_layout      = bids_reader.layout,
                    session          = session,
                    bids_info        = bids_info,
                    db               = db,
                    dataset_tag_dict = dataset_tag_dict,
                    dataset_type     = type
                )
            case (BidsMriDataTypeReader(), _):
                for acquisition, bids_info in data_type_reader.acquisitions:
                    import_bids_mri_acquisition(env, import_env, session, acquisition, bids_info)
            case _:
                print(f"Data type {bids_info.data_type} is not supported. Skipping.")

    # disconnect from the database
    db.disconnect()


def validateids(bids_dir, db, verbose):
    """
    Validate that pscid and candid matches

    :param bids_dir : path to the BIDS directory
     :type bids_dir : str
    :param db       : database handler object
     :type db       : object
    :param verbose      : flag for more printing if set
     :type verbose      : bool
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


def create_loris_bids_directory(bids_reader: BidsDatasetReader, data_dir, verbose):
    """
    Creates the LORIS BIDS import root directory (with name and BIDS version)
    and copy over the dataset_description.json, README and participants.tsv
    files.

    :param bids_reader: BIDS information handler object
     :type bids_reader: object
    :param data_dir   : path of the LORIS data directory
     :type data_dir   : str
    :param verbose    : if true, prints out information while executing
     :type verbose    : bool

    :return: path to the LORIS BIDS import root directory
     :rtype: str
    """

    if bids_reader.dataset_description_file is None:
        print("ERROR: Could not read BIDS dataset description.")
        sys.exit(lib.exitcode.UNREADABLE_FILE)

    # determine the root directory of the LORIS BIDS and create it if does not exist
    name = re.sub(r"[^0-9a-zA-Z]+", "_", bids_reader.dataset_description_file.data['Name'])
    version = re.sub(r"[^0-9a-zA-Z\.]+", "_", bids_reader.dataset_description_file.data['BIDSVersion'])

    # the LORIS BIDS directory will be in data_dir/BIDS/ and named with the
    # concatenation of the dataset name and the BIDS version
    loris_bids_dirname = lib.utilities.create_dir(
        os.path.join(data_dir, 'bids_imports', f'{name}_BIDSVersion_{version}'),
        verbose
    )

    # copy the dataset JSON file to the new directory
    lib.utilities.copy_file(
        bids_reader.path / "dataset_description.json",
        os.path.join(loris_bids_dirname, "dataset_description.json"),
        verbose
    )

    # copy the README file to the new directory
    if os.path.isfile(bids_reader.path / "README"):
        lib.utilities.copy_file(
            bids_reader.path / "README",
            os.path.join(loris_bids_dirname, "README"),
            verbose
        )

    # copy the participant.tsv file to the new directory
    if os.path.exists(os.path.join(loris_bids_dirname, "participants.tsv")):
        lib.utilities.append_to_tsv_file(
            bids_reader.path / "participants.tsv",
            os.path.join(loris_bids_dirname, "participants.tsv"),
            "participant_id",
            verbose
        )
    else:
        lib.utilities.copy_file(
            bids_reader.path / "participants.tsv",
            os.path.join(loris_bids_dirname, "participants.tsv"),
            verbose
        )

    return loris_bids_dirname


def validate_participants(bids_reader: BidsDatasetReader, participants_file: BidsParticipantsTsvFile):
    """
    Validates whether the subjects listed in participants.tsv match the
    list of participant directory. If there is a mismatch, will exit with
    error code from lib.exitcode.
    """

    subjects = bids_reader.subject_labels.copy()

    mismatch_message = ("\nERROR: Participant ID mismatch between "
                        "participants.tsv and raw data found in the BIDS "
                        "directory")

    # check that all subjects listed in participants_info are also in
    # subjects array and vice versa
    for row in participants_file.rows:
        if row.participant_id not in subjects:
            print(mismatch_message)
            print(row.participant_id + 'is missing from the BIDS Layout')
            print('List of subjects parsed by the BIDS layout: ' + ', '.join(subjects))
            sys.exit(lib.exitcode.BIDS_CANDIDATE_MISMATCH)
        # remove the subject from the list of subjects
        subjects.remove(row.participant_id)
    # check that no subjects are left in subjects array
    if subjects:
        print(mismatch_message)
        sys.exit(lib.exitcode.BIDS_CANDIDATE_MISMATCH)


if __name__ == "__main__":
    main()
