#!/usr/bin/env python

"""Script to import BIDS structure into LORIS."""

import json
import os
import re
import sys
from dataclasses import dataclass
from typing import Any, Literal

import lib.exitcode
import lib.physiological
import lib.utilities
from lib.bidsreader import BidsReader
from lib.config import get_data_dir_path_config, get_default_bids_visit_label_config
from lib.database import Database
from lib.db.queries.candidate import try_get_candidate_with_cand_id, try_get_candidate_with_psc_id
from lib.db.queries.session import try_get_session_with_cand_id_visit_label
from lib.eeg import Eeg
from lib.env import Env
from lib.import_bids_dataset.database import check_or_create_bids_candidates_and_sessions
from lib.import_bids_dataset.dataset_files import add_dataset_files
from lib.logging import log, log_error_exit, log_warning
from lib.lorisgetopt import LorisGetOpt
from lib.make_env import make_env
from lib.mri import Mri
from lib.util.crypto import compute_file_blake2b_hash

__license__ = "GPLv3"


sys.path.append('/home/user/python')


bids_eeg_modalities = ['eeg', 'ieeg']

bids_mri_modalities = ['anat', 'dwi', 'fmap', 'func']


@dataclass
class Args:
    source_bids_dir_path: str
    type: Literal[None, 'raw', 'derivative']
    ids_validation: bool
    bids_validation: bool
    create_candidate: bool
    create_session: bool
    copy: bool
    verbose: bool

    def __init__(self, options_dict: dict[str, Any]):
        self.source_bids_dir_path = os.path.normpath(options_dict['directory']['value'])
        self.type                 = options_dict['type']['value']
        self.ids_validation       = options_dict['idsvalidation']['value']
        self.bids_validation      = not options_dict['nobidsvalidation']['value']
        self.create_candidate     = options_dict['createcandidate']['value']
        self.create_session       = options_dict['createsession']['value']
        self.copy                 = not options_dict['nocopy']['value']
        self.verbose              = options_dict['verbose']['value']


# to limit the traceback when raising exceptions.
# sys.tracebacklimit = 0

def main():
    usage = (
        "\n"
        "usage  : bids_import -d <bids_directory> -p <profile> \n"
        "\n"
        "options: \n"
        "\t-p, --profile          : name of the python database config file in dicom-archive/.loris-mri\n"
        "\t-d, --directory        : BIDS directory to parse & insert into LORIS\n"
        "\t                         If directory is within $data_dir/assembly_bids, no copy will be performed\n"
        "\t-c, --createcandidate  : to create BIDS candidates in LORIS (optional)\n"
        "\t-s, --createsession    : to create BIDS sessions in LORIS (optional)\n"
        "\t-i, --idsvalidation    : to validate BIDS directory for a matching pscid/candid pair (optional)\n"
        "\t-b, --nobidsvalidation : to disable BIDS validation for BIDS compliance\n"
        "\t-a, --nocopy           : to disable dataset copy in data assembly_bids\n"
        "\t-t, --type             : raw | derivative. Specify the dataset type.\n"
        "\t                         If not set, the pipeline will look for both raw and derivative files.\n"
        "\t                         Required if no dataset_description.json is found.\n"
        "\t-v, --verbose          : be verbose\n"
    )

    options_dict = {
        "profile": {
            "value": None, "required": True, "expect_arg": True, "short_opt": "p", "is_path": False
        },
        "directory": {
            "value": None, "required": True, "expect_arg": True, "short_opt": "d", "is_path": True
        },
        "createcandidate": {
            "value": False, "required": False, "expect_arg": False, "short_opt": "cc", "is_path": False
        },
        "createsession": {
            "value": False, "required": False, "expect_arg": False, "short_opt": "cc", "is_path": False
        },
        "idsvalidation": {
            "value": False, "required": False, "expect_arg": False, "short_opt": "iv", "is_path": False
        },
        "nobidsvalidation": {
            "value": False, "required": False, "expect_arg": False, "short_opt": "nv", "is_path": False
        },
        "nocopy": {
            "value": False, "required": False, "expect_arg": False, "short_opt": "nc", "is_path": False
        },
        "type": {
            "value": None, "required": False, "expect_arg": True, "short_opt": "t", "is_path": False
        },
        "verbose": {
            "value": False, "required": False, "expect_arg": False, "short_opt": "v", "is_path": False
        },
        "help": {
            "value": False, "required": False, "expect_arg": False, "short_opt": "h", "is_path": False
        },
    }

    # Get the CLI arguments and initiate the environment.

    loris_getopt_obj = LorisGetOpt(usage, options_dict, os.path.basename(__file__[:-3]))

    env = make_env(loris_getopt_obj)

    # Check the CLI arguments.

    type      = loris_getopt_obj.options_dict['type']['value']
    directory = loris_getopt_obj.options_dict['directory']['value']

    dataset_description_path = os.path.join(directory, 'dataset_description.json')
    if not os.path.isfile(dataset_description_path) and type is None:
        log_error_exit(
            env,
            "No 'dataset_description.json' file found. Please run with the --type option.",
            lib.exitcode.MISSING_ARG,
        )

    if type not in [None, 'raw', 'derivative']:
        log_error_exit(
            env,
            f"--type must be one of 'raw', 'derivative'\n{usage}",
            lib.exitcode.MISSING_ARG,
        )

    args = Args(loris_getopt_obj.options_dict)

    # read and insert BIDS data
    read_and_insert_bids(
        env,
        args,
        loris_getopt_obj.db,
    )


def read_and_insert_bids(env: Env, args: Args, legacy_db: Database):
    """
    Read the provided BIDS structure and import it into the database.
    """

    # Validate that pscid and candid matches
    if args.ids_validation:
        validateids(env, args.source_bids_dir_path)

    # load the BIDS directory
    bids_reader = BidsReader(args.source_bids_dir_path, args.verbose, args.bids_validation)

    if (
        bids_reader.bids_participants == []
        or bids_reader.cand_sessions_list == {}
        or bids_reader.cand_session_modalities_list == []
    ):
        log_error_exit(
            env,
            f"Could not properly parse the following BIDS directory: {args.source_bids_dir_path}.",
            lib.exitcode.UNREADABLE_FILE,
        )

    loris_data_dir_path = get_data_dir_path_config(env)

    loris_bids_dir_path = None
    if args.copy:
        # create the LORIS_BIDS directory in data_dir based on Name and BIDS version
        loris_bids_dir_path = create_loris_bids_directory(bids_reader, loris_data_dir_path, args.verbose)

    # Assumption all same project (for project-wide tags)
    single_project_id = None

    check_or_create_bids_candidates_and_sessions(env, bids_reader, args.create_candidate, args.create_session)

    # Import root-level (dataset-wide) events.json
    # Assumption: Single project for project-wide tags
    bids_layout = bids_reader.bids_layout
    root_event_metadata_file = bids_layout.get_nearest(
        loris_bids_dir_path,
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
        log_warning(env, "no events metadata files (event.json) in root directory")
    else:
        # copy the event file to the LORIS BIDS import directory
        copy_file = str.replace(root_event_metadata_file.path, bids_layout.root, '')

        if args.copy:
            event_metadata_path = os.path.join(loris_bids_dir_path, copy_file)
            lib.utilities.copy_file(root_event_metadata_file.path, event_metadata_path, args.verbose)

        # TODO: Move
        hed_query = 'SELECT * FROM hed_schema_nodes WHERE 1'
        hed_union = legacy_db.pselect(query=hed_query, args=())

        # load json data
        with open(root_event_metadata_file.path) as metadata_file:
            event_metadata = json.load(metadata_file)

        blake2 = compute_file_blake2b_hash(root_event_metadata_file.path)
        physio = lib.physiological.Physiological(legacy_db, args.verbose)
        _, dataset_tag_dict = physio.insert_event_metadata(
            event_metadata=event_metadata,
            event_metadata_file=event_metadata_path,
            physiological_file_id=None,
            project_id=single_project_id,
            blake2=blake2,
            project_wide=True,
            hed_union=hed_union
        )

    default_visit_label = get_default_bids_visit_label_config(env)

    # read list of modalities per session / candidate and register data
    for subject_label, session_label, modality in bids_reader.iter_modality_combinations():
        if session_label is not None:
            visit_label = session_label
        else:
            visit_label = default_visit_label

        loris_modality_dir_rel_path = os.path.join(
            f'sub-{subject_label}',
            f'ses-{visit_label}',
            modality,
        )

        loris_modality_dir_path = os.path.join(loris_bids_dir_path, loris_modality_dir_rel_path)
        if os.path.exists(loris_modality_dir_path):
            log(
                env,
                (
                    "Files already inserted in LORIS, skipping:\n"
                    f"- Subject: {subject_label}\n"
                    f"- Session: {visit_label}\n"
                    f"- Modality: {modality}"
                )
            )

            continue

        if args.copy:
            lib.utilities.create_dir(loris_modality_dir_path, args.verbose)

        if modality in bids_eeg_modalities:
            Eeg(
                bids_reader   = bids_reader,
                bids_sub_id   = subject_label,
                bids_ses_id   = session_label,
                bids_modality = modality,
                db            = legacy_db,
                verbose       = args.verbose,
                data_dir      = loris_data_dir_path,
                default_visit_label    = default_visit_label,
                loris_bids_eeg_rel_dir = loris_modality_dir_rel_path,
                loris_bids_root_dir    = loris_bids_dir_path,
                dataset_tag_dict       = dataset_tag_dict,
                dataset_type           = args.type
            )
        elif modality in bids_mri_modalities:
            candidate = try_get_candidate_with_psc_id(env.db, subject_label)
            session = try_get_session_with_cand_id_visit_label(env.db, candidate.cand_id, visit_label)

            Mri(
                env           = env,
                session       = session,
                bids_reader   = bids_reader,
                bids_sub_id   = subject_label,
                bids_ses_id   = session_label,
                bids_modality = modality,
                data_dir      = loris_data_dir_path,
                loris_bids_mri_rel_dir = loris_modality_dir_rel_path,
                loris_bids_root_dir    = loris_bids_dir_path
            )

    if args.copy:
        add_dataset_files(env, args.source_bids_dir_path, loris_bids_dir_path, args.verbose)


def validateids(env: Env, bids_dir: str):
    """
    Validate that pscid and candid matches

    :param bids_dir : path to the BIDS directory
    :param db       : database handler object
    :param verbose  : flag for more printing if set
    """

    bids_folder = bids_dir.split('/')[-1]
    bids_folder_parts = bids_folder.split('_')
    psc_id = bids_folder_parts[0]
    cand_id = bids_folder_parts[1]

    try:
        cand_id = int(cand_id)
    except ValueError:
        log_error_exit(
            env,
            f"{cand_id} is not a valid CandID.",
            lib.exitcode.CANDIDATE_NOT_FOUND,
        )

    candidate = try_get_candidate_with_cand_id(env.db, cand_id)

    if candidate is None:
        log_error_exit(
            env,
            f"Could not find a candidate with CandID {cand_id}.",
            lib.exitcode.CANDID_NOT_FOUND,
        )

    if candidate.psc_id != psc_id:
        log_error_exit(
            env,
            f"CandID {cand_id} and PSCID {psc_id} do not match in the database."
        )


def create_loris_bids_directory(bids_reader: BidsReader, loris_data_dir: str, verbose: bool) -> str:
    """
    Creates the LORIS BIDS import root directory (with name and BIDS version)
    and copy over the dataset_description.json, README and participants.tsv
    files.

    :param bids_reader : BIDS information handler object
    :param data_dir    : path of the LORIS data directory
    :param verbose     : if true, prints out information while executing

    :return: path to the LORIS BIDS import root directory
    """

    # determine the root directory of the LORIS BIDS and create it if does not exist
    dataset_name    = re.sub(r'[^0-9a-zA-Z]+',   '_', bids_reader.dataset_name)  # get name of the dataset
    dataset_version = re.sub(r'[^0-9a-zA-Z\.]+', '_', bids_reader.bids_version)  # get BIDSVersion of the dataset

    # the LORIS BIDS directory will be in data_dir/BIDS/ and named with the
    # concatenation of the dataset name and the BIDS version
    loris_bids_dir_path = lib.utilities.create_dir(
        os.path.join(loris_data_dir, 'bids_imports', f'{dataset_name}_BIDSVersion_{dataset_version}'),
        verbose
    )

    return loris_bids_dir_path


if __name__ == '__main__':
    main()
