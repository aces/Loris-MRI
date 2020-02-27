#!/usr/bin/env python

"""Script to validate a DICOM archive from the filesystem against the one stored in the database"""

import getopt
import os
import sys

import lib.exitcode
import lib.utilities as utilities
from lib.database import Database
from lib.imaging  import Imaging
from lib.database_lib.config       import Config
from lib.database_lib.mriupload    import MriUpload
from lib.database_lib.mriscanner   import MriScanner
from lib.database_lib.notification import Notification
from lib.database_lib.tarchive     import Tarchive

__license__ = "GPLv3"


sys.path.append('/home/user/python')

# to limit the traceback when raising exceptions.
#sys.tracebacklimit = 0

def main():
    profile   = ''
    upload_id = 0
    verbose   = False
    tarchive_path = ''

    long_options = ['help', 'profile=', 'tarchive=', 'uploadid=', 'verbose']

    usage = (
        '\n'
        
        '********************************************************************\n'
        ' DICOM ARCHIVE VALIDATOR\n'
        '********************************************************************\n\n'
        'The program does the following validations on a DICOM archive given as an argument:\n'
        '\t- Verify the DICOM archive against the checksum stored in the database\n'
        '\t- Verify the PSC information using either PatientName or PatientID DICOM header\n'
        '\t- Verify/determine the ScannerID (optionally create a new one if necessary)\n'
        '\t- Verify the candidate IDs are valid\n'
        '\t- Verify the session is valid\n'
        '\t- Update the mri_upload\'s isTarchiveValidated field if above validations were successful\n\n'
        
        'usage  : dicom_archive_validation -p <profile> -t <tarchive_path> -u <upload_id>\n\n'
        
        'options: \n'
        '\t-p, --profile     : Name of the python database config file in '
                               'dicom-archive/.loris_mri\n'
        '\t-t, --tarchive    : Path to the DICOM archive to validate\n'
        '\t-u, --uploadid    : UploadID associated to the DICOM archive to validate\n'
        '\t-v, --verbose     : Be verbose'
    )

    try:
        opts, args = getopt.getopt(sys.argv[1:], 'hp:t:u:v', long_options)
    except getopt.GetoptError as err:
        print(usage)
        sys.exit(lib.exitcode.GETOPT_FAILURE)

    for opt, arg in opts:
        if opt in ('-h', '--help'):
            print(usage)
            sys.exit()
        elif opt in ('-p', '--profile'):
            profile = os.environ['LORIS_CONFIG'] + '/.loris_mri/' + arg
        elif opt in ('-t', '--tarchive'):
            tarchive_path = arg
        elif opt in ('-u', '--uploadid'):
            upload_id = arg
        elif opt in ('-v', '--verbose'):
            verbose = True

    # input error checking and load config_file file
    config_file = input_error_checking(profile, tarchive_path, upload_id, usage)

    # validate the DICOM archive
    validate_dicom_archive(config_file, tarchive_path, upload_id, verbose)


def input_error_checking(profile, tarchive_path, upload_id, usage):
    """
    Checks whether the required inputs are set and that paths are valid. If
    the path to the config_file file valid, then it will import the file as a
    module so the database connection information can be used to connect.

    :param profile      : path to the profile file with MySQL credentials
     :type profile      : str
    :param tarchive_path: path to the DICOM archive to validate against the database entry
     :type tarchive_path: str
    :param upload_id    : UploadID associated to the DICOM archive
     :type upload_id    : str
    :param usage        : script usage to be displayed when encountering an error
     :type usage        : str

    :return: config_file module with database credentials (config_file.mysql)
     :rtype: module
    """

    if not profile:
        message = '\n\tERROR: you must specify a profile file using -p or ' \
                  '--profile option'
        print(message)
        print(usage)
        sys.exit(lib.exitcode.MISSING_ARG)

    if not tarchive_path:
        message = '\n\tERROR: you must specify a DICOM archive path using -t or ' \
                  '--tarchive option'
        print(message)
        print(usage)
        sys.exit(lib.exitcode.MISSING_ARG)

    if not upload_id:
        message = '\n\tERROR: you must specify an UploadID using -u or ' \
                  '--uploadid option'
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

    if not os.path.isfile(tarchive_path):
        message = '\n\tERROR: you must specify a valid DICOM archive path.\n' + \
                  tarchive_path + ' does not exist!'
        print(message)
        print(usage)
        sys.exit(lib.exitcode.INVALID_PATH)

    try:
        int(upload_id)
    except ValueError:
        message = '\n\tERROR: you must specify an integer value for --uploadid option.\n'
        print(message)
        print(usage)

    return config_file


def validate_dicom_archive(config_file, tarchive_path, upload_id, verbose):
    """
    Performs the different DICOM archive validations. This includes:
      - Verification of the DICOM archive against the checksum stored in the database
      - Verification of the PSC information using either PatientName or PatientID DICOM header
      - Verification of the ScannerID in the database (optionally create a new one if necessary)
      - Validity check of the candidate IDs associated to the DICOM archive based on the PatientName
      - Validity check of the session associated to the DICOM archive based on the PatientName
      - Update to the mri_upload's isTarchiveValidated field if above validations were successful

    :param config_file         : path to the config file with MySQL credentials
     :type config_file         : str
    :param tarchive_path       : path to the DICOM archive to validate against the database entries
     :type tarchive_path       : str
    :param upload_id           : UploadID associated to the DICOM archive
     :type upload_id           : int
    :param verbose             : be verbose
     :type verbose             : bool
    """

    # ----------------------------------------------------
    # establish database connection
    # ----------------------------------------------------
    db = Database(config_file.mysql, verbose)
    db.connect()

    # -----------------------------------------------------------------------------------
    # load the Config, Imaging, Tarchive, MriUpload, MriScanner and Notification classes
    # -----------------------------------------------------------------------------------
    config_obj       = Config(db, verbose)
    imaging_obj      = Imaging(db, verbose, config_file)
    tarchive_obj     = Tarchive(db, verbose, config_file)
    mri_upload_obj   = MriUpload(db, verbose)
    mri_scanner_obj  = MriScanner(db, verbose)
    notification_obj = Notification(
        db,
        verbose,
        notification_type='python DICOM archive validation',
        notification_origin='dicom_archive_validation.py',
        process_id=upload_id
    )

    # ---------------------------------------------------------------------------------------------
    # grep config settings from the Config module & ensure that there is a final / in dicom_lib_dir
    # ---------------------------------------------------------------------------------------------
    dicom_lib_dir = config_obj.get_config('tarchiveLibraryDir')
    dicom_lib_dir = dicom_lib_dir if dicom_lib_dir.endswith('/') else dicom_lib_dir + "/"

    # ----------------------------------------------------
    # determine the archive location
    # ----------------------------------------------------
    archive_location = tarchive_path.replace(dicom_lib_dir, '')

    # -------------------------------------------------------------------------------
    # update the mri_upload table to indicate that a script is running on the upload
    # -------------------------------------------------------------------------------
    mri_upload_obj.update_mri_upload(upload_id=upload_id, fields=('Inserting',), values=('1',))

    # ---------------------------------------------------------------------------------
    # create the DICOM archive array (that will be in tarchive_obj.tarchive_info_dict)
    # ---------------------------------------------------------------------------------
    success = tarchive_obj.create_tarchive_dict(archive_location, None)
    if not success:
        message = 'ERROR: Only archive data can be uploaded. This seems not to be a valid' \
                  ' archive for this study!'
        notification_obj.write_to_notification_spool(message=message, is_error='Y', is_verbose='N')
        print('\n' + message + '\n\n')
        mri_upload_obj.update_mri_upload(
            upload_id = upload_id,
            fields    = ('isTarchiveValidated', 'Inserting', 'IsCandidateInfoValidated'),
            values    = ('0',                   '0',         '0'                       )
        )
        sys.exit(lib.exitcode.INVALID_DICOM)
    else:
        tarchive_id = tarchive_obj.tarchive_info_dict['TarchiveID']
        mri_upload_obj.update_mri_upload(
            upload_id=upload_id, fields=('TarchiveID',), values=(tarchive_id,)
        )
    tarchive_info_dict = tarchive_obj.tarchive_info_dict

    # ------------------------------------------------------------------------------
    # verify the md5sum of the DICOM archive against the one stored in the database
    # ------------------------------------------------------------------------------
    message = '==> verifying DICOM archive md5sum (checksum)'
    notification_obj.write_to_notification_spool(message=message, is_error='N', is_verbose='Y')
    if verbose:
        print('\n' + message + '\n')
    result  = tarchive_obj.validate_dicom_archive_md5sum(tarchive_path)
    message = result['message']
    if result['success']:
        notification_obj.write_to_notification_spool(message=message, is_error='N', is_verbose='Y')
        if verbose:
            print('\n' + message + '\n')
    else:
        notification_obj.write_to_notification_spool(message=message, is_error='Y', is_verbose='N')
        print('\n' + message + '\n\n')
        mri_upload_obj.update_mri_upload(
            upload_id = upload_id,
            fields    = ('isTarchiveValidated', 'Inserting', 'IsCandidateInfoValidated'),
            values    = ('0',                   '0',         '0')
        )
        sys.exit(lib.exitcode.CORRUPTED_FILE)

    # ----------------------------------------------------
    # verify PSC information stored in DICOMs
    # ----------------------------------------------------
    site_dict = imaging_obj.determine_study_center(tarchive_info_dict)
    if 'error' in site_dict.keys():
        message = site_dict['message']
        notification_obj.write_to_notification_spool(message=message, is_error='Y', is_verbose='N')
        print('\n' + message + '\n\n')
        mri_upload_obj.update_mri_upload(
            upload_id = upload_id,
            fields    = ('isTarchiveValidated', 'Inserting', 'IsCandidateInfoValidated'),
            values    = ('0',                   '0',         '0')
        )
        sys.exit(site_dict['exit_code'])
    center_id   = site_dict['CenterID']
    center_name = site_dict['CenterName']
    message = '==> Found Center Name: ' + center_name + ', Center ID: ' + str(center_id)
    notification_obj.write_to_notification_spool(message=message, is_error='N', is_verbose='Y')
    if verbose:
        print('\n' + message + '\n')

    # ---------------------------------------------------------------
    # grep scanner information based on what is in the DICOM headers
    # ---------------------------------------------------------------
    scanner_dict = mri_scanner_obj.determine_scanner_information(tarchive_info_dict, site_dict)
    message      = '===> Found Scanner ID: ' + str(scanner_dict['ScannerID'])
    notification_obj.write_to_notification_spool(message=message, is_error='N', is_verbose='Y')
    if verbose:
        print('\n' + message + '\n')

    # ---------------------------------------------------------------------------------
    # determine subject IDs based on DICOM headers and validate the IDs against the DB
    # ---------------------------------------------------------------------------------
    subject_id_dict       = imaging_obj.determine_subject_ids(tarchive_info_dict, scanner_dict['ScannerID'])
    is_subject_info_valid = imaging_obj.validate_subject_ids(subject_id_dict)
    if not is_subject_info_valid:
        # note: the script will not exit so that further down it can be inserted per
        # NIfTI file into MRICandidateErrors
        notification_obj.write_to_notification_spool(message=message, is_error='Y', is_verbose='N')
        print(subject_id_dict['CandMismatchError'])
        mri_upload_obj.update_mri_upload(
            upload_id=upload_id, fields=('IsCandidateInfoValidated',), values=('0',)
        )
    else:
        message = subject_id_dict['message']
        notification_obj.write_to_notification_spool(message=message, is_error='N', is_verbose='Y')
        mri_upload_obj.update_mri_upload(
            upload_id=upload_id, fields=('IsCandidateInfoValidated',), values=('1',)
        )

    # -----------------------------------------------------
    # update mri_upload table with IsTarchiveValidated = 1
    # -----------------------------------------------------
    mri_upload_obj.update_mri_upload(
        upload_id = upload_id,
        fields    = ('isTarchiveValidated', 'Inserting'),
        values    = ('1',                   '0'        )
    )


if __name__ == "__main__":
    main()