#!/usr/bin/env python3

"""Script that handles deletion of EEG files"""

import os
import shutil
import sys

from lib.database import Database
from lib.database_lib.config import Config
from lib.exitcode import INVALID_ARG
from lib.lorisgetopt import LorisGetOpt


def main():
    usage = (
        "\n"

        "********************************************************************\n"
        " DELETE PHYSIOLOGICAL FILE \n"
        "********************************************************************\n"
        "This script deletes all the data associated with an EEG file"

        "usage  : delete_physiological_file.py -f file_id -p <profile> ...\n\n"

        "options: \n"
        "\t-p, --profile      : Name of the python database config file in config\n"
        "\t-f, --fileid       : Id of the file (PhysiologicalFileID) to delete\n"
        "\t-c, --confirm      : After a trial run, perform the deletion\n"
        "\t-d, --deleteondisk : Delete files on disk\n"
        "\t-v, --verbose      : If set, be verbose\n\n"

        "required options are: \n"
        "\t--profile\n"
        "\t--fileid\n"
    )

    options_dict = {
        "profile": {
            "value": None, "required": True, "expect_arg": True, "short_opt": "p", "is_path": False
        },
        "fileid": {
            "value": None, "required": True, "expect_arg": True, "short_opt": "f", "is_path": False
        },
        "confirm": {
            "value": None, "required": False, "expect_arg": False, "short_opt": "c", "is_path": False
        },
        "deleteondisk": {
            "value": None, "required": False, "expect_arg": False, "short_opt": "d", "is_path": False
        },
        "verbose": {
            "value": False, "required": False, "expect_arg": False, "short_opt": "v", "is_path": False
        },
        "help": {
            "value": False, "required": False, "expect_arg": False, "short_opt": "h", "is_path": False
        },
    }

    # ---------------------------------------------------------------------------------------------
    # Get the options provided by the user
    # ---------------------------------------------------------------------------------------------
    loris_getopt_obj = LorisGetOpt(usage, options_dict, os.path.basename(__file__[:-3]))
    file_id = loris_getopt_obj.options_dict['fileid']['value']
    confirm = loris_getopt_obj.options_dict['confirm']['value']
    deleteondisk = loris_getopt_obj.options_dict['deleteondisk']['value']
    verbose = loris_getopt_obj.options_dict['verbose']['value']

    # ---------------------------------------------------------------------------------------------
    # Establish database connection
    # ---------------------------------------------------------------------------------------------
    db = Database(loris_getopt_obj.config_info.mysql, verbose)
    db.connect()

    # ---------------------------------------------------------------------------------------------
    # Load the configs
    # ---------------------------------------------------------------------------------------------
    config_db_obj = Config(db, verbose)
    data_path = config_db_obj.get_config("dataDirBasepath")

    # ---------------------------------------------------------------------------------------------
    # Run the script
    # ---------------------------------------------------------------------------------------------
    validate_file_id(db, file_id)
    delete_physiological_file(db, data_path, file_id, confirm, deleteondisk)


def validate_file_id(db, file_id):
    """
    Check that the file id exists in the database

    :param db: database object from the database.py class
     :type db: Database
    :param file_id: file id
     :type file_id: int
    """

    file_exists = db.pselect(
        """
        SELECT COUNT(*)
        FROM physiological_file
        WHERE PhysiologicalFileID = %s
        """,
        (file_id,)
    )

    if (file_exists == 0):
        print(f"\nThe physiological file with id : {file_id} does not exist in the database.\n")
        sys.exit(INVALID_ARG)


def delete_physiological_file_in_db(db, file_id):
    print(f"\nDropping all DB entries for physiological file: {file_id}\n")
    print("----------------------------\n")

    print("Delete physiological_event_parameter_category_level\n")
    event_parameter_ids = db.pselect(
        """
        SELECT EventParameterID
        FROM physiological_event_parameter
        JOIN physiological_event_file USING(EventFileID)
        WHERE PhysiologicalFileID = %s
        """,
        (file_id,)
    )

    for event_parameter_id in event_parameter_ids:
        db.update(
            """
            DELETE FROM physiological_event_parameter_category_level
            WHERE EventParameterID = %s
            """,
            (event_parameter_id["EventParameterID"],)
        )

    print("Delete physiological_event_parameter\n")
    event_file_ids = db.pselect(
        """
        SELECT EventFileID
        FROM physiological_event_file
        WHERE PhysiologicalFileID = %s
        """,
        (file_id,)
    )

    for event_file_id in event_file_ids:
        db.update(
            """
            DELETE FROM physiological_event_parameter
            WHERE EventFileID = %s
            """,
            (event_file_id["EventFileID"],)
        )

    print("Delete physiological_channel\n")
    db.update(
        """
        DELETE FROM physiological_channel
        WHERE PhysiologicalFileID = %s
        """,
        (file_id,)
    )

    print("Delete physiological_electrode\n")
    electrode_ids = db.pselect(
        """
        SELECT PhysiologicalElectrodeID
        FROM physiological_coord_system_electrode_rel
        WHERE PhysiologicalFileID = %s
        """,
        (file_id,)
    )

    print("Delete physiological_coord_system_point_3d_rel\n")
    # delete all couple from physiological_coord_system_point_3d_rel
    # that are linked to the selected physiological file
    coord_system_point_rel = db.pselect(
        """
        SELECT ppr.PhysiologicalCoordSystemID, ppr.Point3DID
        FROM physiological_coord_system_point_3d_rel AS ppr
            INNER JOIN physiological_coord_system AS p
                USING (PhysiologicalCoordSystemID)
            INNER JOIN physiological_coord_system_electrode_rel AS per
                USING (PhysiologicalCoordSystemID)
        WHERE per.PhysiologicalFileID = %s
        """,
        (file_id,)
    )
    for row in coord_system_point_rel:
        db.update(
            """
            DELETE FROM physiological_coord_system_point_3d_rel
            WHERE PhysiologicalCoordSystemID = %s
            AND Point3DID = %s
            """,
            (row["PhysiologicalCoordSystemID"], row["Point3DID"],)
        )

    print("Delete point_3d\n")
    # delete from point_3d not linked to any physiological_electrode
    # and physiological_coord_system_point_3d_rel
    point_3d_ids = db.pselect(
        """
        SELECT Point3DID
        FROM point_3d
        WHERE Point3DID NOT IN (
            SELECT Point3DID FROM physiological_coord_system_point_3d_rel
        ) AND Point3DID NOT IN (
            SELECT Point3DID FROM physiological_electrode
        )
        """,
        ()
    )
    for point_3d_id in point_3d_ids:
        db.update(
            """
            DELETE FROM point_3d
            WHERE Point3DID = %s
            """,
            (point_3d_id["Point3DID"],)
        )

    print("Delete physiological_coord_system\n")
    # delete physiological_coord_system if not linked to any other
    # physiological_coord_system_electrode_rel
    # or physiological_coord_system_point_3d_rel
    coord_system_ids = db.pselect(
        """
        SELECT PhysiologicalCoordSystemID
        FROM physiological_coord_system
        WHERE PhysiologicalCoordSystemID NOT IN (
            SELECT PhysiologicalCoordSystemID
            FROM physiological_coord_system_point_3d_rel
        ) AND PhysiologicalCoordSystemID NOT IN (
            SELECT PhysiologicalCoordSystemID
            FROM physiological_coord_system_electrode_rel
        )
        """,
        ()
    )
    for coord_system_id in coord_system_ids:
        db.update(
            """
            DELETE FROM physiological_coord_system
            WHERE PhysiologicalCoordSystemID = %s
            """,
            (coord_system_id["PhysiologicalCoordSystemID"],)
        )

    print("Delete physiological_coord_system_electrode_rel\n")
    db.update(
        """
        DELETE FROM physiological_coord_system_electrode_rel
        WHERE PhysiologicalFileID = %s
        """,
        (file_id,)
    )

    print("Delete physiological_electrode\n")
    for electrode_id in electrode_ids:
        db.update(
            """
            DELETE FROM physiological_electrode
            WHERE PhysiologicalElectrodeID = %s
            """,
            (electrode_id["PhysiologicalElectrodeID"],)
        )

    print("Delete physiological_parameter_file\n")
    db.update(
        """
        DELETE FROM physiological_parameter_file
        WHERE PhysiologicalFileID = %s
        """,
        (file_id,)
    )

    print("Delete physiological_archive\n")
    db.update(
        """
        DELETE FROM physiological_archive
        WHERE PhysiologicalFileID = %s
        """,
        (file_id,)
    )

    print("Delete physiological_event_archive\n")
    db.update(
        """
        DELETE FROM physiological_event_archive
        WHERE PhysiologicalFileID = %s
        """,
        (file_id,)
    )

    print("Delete physiological_task_event_opt\n")
    print("Delete physiological_task_event_hed_rel\n")
    task_event_ids = db.pselect(
        """
        SELECT PhysiologicalTaskEventID
        FROM physiological_task_event
        WHERE PhysiologicalFileID = %s
        """,
        (file_id,)
    )

    for task_event_id in task_event_ids:
        db.update(
            """
            DELETE FROM physiological_task_event_opt
            WHERE PhysiologicalTaskEventID = %s
            """,
            (task_event_id["PhysiologicalTaskEventID"],)
        )
        db.update(
            """
            DELETE FROM physiological_task_event_hed_rel
            WHERE PhysiologicalTaskEventID = %s
            """,
            (task_event_id["PhysiologicalTaskEventID"],)
        )

    print("Delete physiological_task_event\n")
    db.update(
        """
        DELETE FROM physiological_task_event
        WHERE PhysiologicalFileID = %s
        """,
        (file_id,)
    )

    print("Delete physiological_event_file\n")
    db.update(
        """
        DELETE FROM physiological_event_file
        WHERE PhysiologicalFileID = %s
        """,
        (file_id,)
    )

    print("Delete physiological_file\n")
    db.update(
        """
        DELETE FROM physiological_file
        WHERE PhysiologicalFileID = %s
        """,
        (file_id,)
    )


def delete_physiological_file(db, data_path, file_id, confirm, deleteondisk):
    """
    Deletes the provided physiological file and all its associated metadata in the db
    as well as on the file system

    :param db: database object from the database.py class
     :type db: Database
    :param data_path: data path where files are stored on disk
     :type data_path: string
    :param file_id: file id
     :type file_id: int
    :param confirm: flag to turn on deletion
     :type confirm: boolean
    :param deleteondisk: flag to turn on file deletion
     :type deleteondisk: boolean
    """

    files = []

    print("\nArchives")
    print("----------------------------")
    archives = db.pselect(
        """
        SELECT FilePath
        FROM physiological_archive
        WHERE PhysiologicalFileID = %s
        """,
        (file_id,)
    )
    files.extend(archives)
    print(archives)

    print("\nPhysiological File")
    print("----------------------------")
    eeg_files = db.pselect(
        """
        SELECT DISTINCT FilePath
        FROM physiological_file
        JOIN physiological_output_type USING(PhysiologicalOutputTypeID)
        WHERE PhysiologicalFileID = %s
        """,
        (file_id,)
    )
    files.extend(eeg_files)
    print(eeg_files)

    print("\nPhysiological Metadata File")
    print("----------------------------")
    metadata_files = db.pselect(
        """
        SELECT DISTINCT ppf.Value AS FilePath
        FROM physiological_parameter_file AS ppf
        LEFT JOIN parameter_type AS pt USING (ParameterTypeID)
        WHERE PhysiologicalFileID = %s
        AND pt.Name = "eegjson_file"
        """,
        (file_id,)
    )
    files.extend(metadata_files)
    print(metadata_files)

    print("\nChannels")
    print("----------------------------")
    channels = db.pselect(
        """
        SELECT DISTINCT FilePath
        FROM physiological_channel
        WHERE PhysiologicalFileID = %s
        """,
        (file_id,)
    )
    files.extend(channels)
    print(channels)

    print("\nElectrodes")
    print("----------------------------")
    electrodes = db.pselect(
        """
        SELECT DISTINCT FilePath
        FROM physiological_electrode
        LEFT JOIN physiological_coord_system_electrode_rel
        USING (PhysiologicalElectrodeID)
        WHERE PhysiologicalFileID = %s
        """,
        (file_id,)
    )
    files.extend(electrodes)
    print(electrodes)

    print("\nCoordinate Systems")
    print("----------------------------")
    coordinate_systems = db.pselect(
        """
        SELECT DISTINCT PhysiologicalFileID, FilePath
        FROM physiological_coord_system
        JOIN physiological_coord_system_electrode_rel
        USING (PhysiologicalCoordSystemID)
        WHERE FilePath IS NOT NULL
        HAVING count(PhysiologicalFileID) = 1
        AND PhysiologicalFileID = %s
        """,
        (file_id,)
    )
    files.extend(coordinate_systems)
    print(coordinate_systems)

    print("\nEvent Files")
    print("----------------------------")
    event_files = db.pselect(
        """
        SELECT DISTINCT FilePath
        FROM physiological_event_file
        WHERE PhysiologicalFileID = %s
        """,
        (file_id,)
    )
    files.extend(event_files)
    print(event_files)

    print("\nEvent Archives")
    print("----------------------------")
    event_archives = db.pselect(
        """
        SELECT DISTINCT FilePath
        FROM physiological_event_archive
        WHERE PhysiologicalFileID = %s
        """,
        (file_id,)
    )
    files.extend(event_archives)
    print(event_archives)

    print("\nChunks")
    print("----------------------------")
    chunks = db.pselect(
        """
        SELECT ppf.Value AS FilePath
        FROM physiological_parameter_file AS ppf
        LEFT JOIN parameter_type AS pt USING (ParameterTypeID)
        WHERE PhysiologicalFileID = %s
        AND pt.Name = "electrophysiology_chunked_dataset_path"
        """,
        (file_id,)
    )
    print(chunks)

    # IF CONFIRMED, DELETE ENTRIES AND FILES
    if confirm:
        delete_physiological_file_in_db(db, file_id)

        if deleteondisk:
            print(f"\nDeleting files on disk for physiological file: {file_id}\n")
            print("----------------------------\n")

            for file in files:
                print(f"Deleting file {file['FilePath']}\n")
                try:
                    os.remove(os.path.join(data_path, file['FilePath']))
                except Exception as e:
                    print(f"Caught exception: {e} \n")

            for chunk in chunks:
                try:
                    shutil.rmtree(os.path.join(data_path, chunk['FilePath']))
                except Exception as e:
                    print(f"Caught exception: {e} \n")

    else:
        print("\nRun this tool again with argument --confirm to confirm database entries deletion.")
        print("To also delete files on disk, run with both --confirm and optional argument --deleteondisk.\n")


if __name__ == "__main__":
    main()
