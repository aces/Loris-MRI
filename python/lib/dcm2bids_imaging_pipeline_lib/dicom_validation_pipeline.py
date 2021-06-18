import os

import lib.exitcode
from lib.dcm2bids_imaging_pipeline_lib.base_pipeline import BasePipeline

__license__ = "GPLv3"


class DicomValidationPipeline(BasePipeline):

    def __init__(self, loris_getopt_obj, script_name):
        super().__init__(loris_getopt_obj, script_name)
        self.validate_subject_ids()
        self._validate_dicom_archive_md5sum()

        # ---------------------------------------------------------------------------------------------
        # If we get here, the tarchive is validated & the script stops running so update mri_upload
        # ---------------------------------------------------------------------------------------------
        message = f"DICOM archive {self.options_dict['tarchive_path']['value']} is valid!"
        self.log_info(message, is_error="N", is_verbose="Y")
        self.mri_upload_db_obj.update_mri_upload(
            upload_id=self.upload_id,
            fields=("isTarchiveValidated", "Inserting",),
            values=("1", "0")
        )

    def _validate_dicom_archive_md5sum(self):

        self.log_info(message="Verifying DICOM archive md5sum (checksum)", is_error="N", is_verbose="Y")

        tarchive_path = os.path.join(self.dicom_lib_dir, self.tarchive_db_obj.tarchive_info_dict["ArchiveLocation"])
        result = self.tarchive_db_obj.validate_dicom_archive_md5sum(tarchive_path)
        message = result["message"]

        if result['success']:
            self.log_info(message, is_error="N", is_verbose="Y")
        else:
            self.mri_upload_db_obj.update_mri_upload(
                upload_id=self.upload_id,
                fields=("isTarchiveValidated", "IsCandidateInfoValidated"),
                values=("0", "0")
            )
            self.log_error_and_exit(message, lib.exitcode.CORRUPTED_FILE, is_error="Y", is_verbose="N")
