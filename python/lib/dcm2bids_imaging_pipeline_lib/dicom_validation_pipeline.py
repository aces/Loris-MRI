import os
import sys

from loris_utils.crypto import compute_file_md5_hash

import lib.exitcode
from lib.db.models.dicom_archive import DbDicomArchive
from lib.dcm2bids_imaging_pipeline_lib.base_pipeline import BasePipeline
from lib.env import Env
from lib.logging import log_error_exit, log_verbose


class DicomValidationPipeline(BasePipeline):
    """
    Pipeline that extends the BasePipeline class to add some specific DICOM validations to be
    run to validate the DICOM archive processed.

    Functions that starts with _ are functions specific to the DicomValidationPipeline class.
    """

    def __init__(self, loris_getopt_obj, script_name):
        """
        Initiate the DicomValidationPipeline class and runs the different validations that need to
        be run on the DICOM archive. The mri_upload table will be updated according to the finding
        of the DICOM archive validation.

        :param loris_getopt_obj: the LorisGetOpt object with getopt values provided to the pipeline
         :type loris_getopt_obj: LorisGetOpt obj
        :param script_name: name of the script calling this class
         :type script_name: str
        """
        super().__init__(loris_getopt_obj, script_name)
        self.init_session_info()
        self._validate_dicom_archive_md5sum()

        # ---------------------------------------------------------------------------------------------
        # If we get here, the tarchive is validated & the script stops running so update mri_upload
        # ---------------------------------------------------------------------------------------------
        log_verbose(self.env, f"DICOM archive {self.options_dict['tarchive_path']['value']} is valid!")

        # Update the MRI upload.
        self.mri_upload.is_dicom_archive_validated = True
        self.mri_upload.inserting = False
        self.env.db.commit()

        self.remove_tmp_dir()  # remove temporary directory
        sys.exit(lib.exitcode.SUCCESS)

    def _validate_dicom_archive_md5sum(self):
        """
        Validates that the DICOM archive stored on the file system has the same md5sum than the one
        logged in the <tarchive> table.
        """

        log_verbose(self.env, "Verifying DICOM archive md5sum (checksum)")

        dicom_archive_path = os.path.join(self.dicom_lib_dir, self.dicom_archive.archive_path)
        result = _validate_dicom_archive_md5sum(self.env, self.dicom_archive, dicom_archive_path)
        if not result:
            # Update the MRI upload.
            self.mri_upload.is_dicom_archive_validated = False
            self.mri_upload.is_candidate_info_validated = False
            self.env.db.commit()

            log_error_exit(
                self.env,
                "ERROR: DICOM archive seems corrupted or modified. Upload will exit now.",
                lib.exitcode.CORRUPTED_FILE,
            )


def _validate_dicom_archive_md5sum(env: Env, dicom_archive: DbDicomArchive, dicom_archive_path: str) -> bool:
    """
    This function validates that the md5sum of the DICOM archive on the filesystem is the same
    as the md5sum of the registered entry in the tarchive table.

    Retrun `true` if the MD5 sums match, or `false` if they don't.
    """

    # compute the md5sum of the tarchive file
    dicom_archive_file_md5_sum = compute_file_md5_hash(dicom_archive_path)

    # grep the md5sum stored in the database
    dicom_archive_db_md5_sum = dicom_archive.md5_sum_archive.split()[0]

    log_verbose(
        env,
        f"checksum for target: {dicom_archive_file_md5_sum};  checksum from database: {dicom_archive_db_md5_sum}",
    )

    # check that the two md5sum are the same
    return dicom_archive_file_md5_sum == dicom_archive_db_md5_sum
