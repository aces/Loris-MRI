import os
import subprocess
import tarfile

from lib.dcm2bids_imaging_pipeline_lib.base_pipeline import BasePipeline

__license__ = "GPLv3"


class DicomArchiveLoaderPipeline(BasePipeline):

    def __init__(self, loris_getopt_obj, script_name):
        super().__init__(loris_getopt_obj, script_name)
        self.series_uid = self.options_dict["series_uid"]["value"]

        # ---------------------------------------------------------------------------------------------
        # Run the DICOM archive validation script to check if the DICOM archive is valid
        # ---------------------------------------------------------------------------------------------
        self.run_dicom_archive_validation_pipeline()

        # ---------------------------------------------------------------------------------------------
        # Extract DICOM files from the tarchive
        # ---------------------------------------------------------------------------------------------
        self.extracted_dicom_dir = self.extract_dicom_files()

        # TODO:
        # - Get series description to exclude from processing
        # - Extract DICOM files
        # - Run dcm2niix with BIDS non anonymized option
        # - Get count of NIfTI files to process
        # - Loop through generated NIfTI files to run nifti insertion
        #     - move DICOM archive to year subfolder and update tarchive table if at least one file inserted
        #     - call run_nifti_insertion.py - get return code (run with create_pic option)
        #           => if success add to number of NIfTI inserted and set valid_study to 1
        # - Compute SNR (find an equivalent for NIfTI files
        # - order modality by acquisition number
        # - if valid_study, update numbers of file inserted
        # - update SessionID in tarchive and mri_upload
        # - figure out how to log files moved to trashbin (done by NIfTI insertion script directly)

    def run_dicom_archive_validation_pipeline(self):
        """
        Runs the script `run_dicom_archive_validation.py` to ensure the DICOM archive to process is valid.
        Once the script is done running, check in the database that the mri_upload table was properly updated.
        If not, self.check_if_tarchive_validated_in_db() will exit and log the error in the notification spool
        table and log files.
        """

        validation_process = subprocess.Popen(
            [
                "run_dicom_archive_validation.py",
                f"-p {self.options_dict['profile']['value']}",
                f"-t {self.options_dict['tarchive_path']['value']}",
                f"-u {self.options_dict['upload_id']['value']}"
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT
        )
        validation_process.communicate()

        # now that the DICOM archive validation has run, check the database to ensure the validation was completed
        self.check_if_tarchive_validated_in_db()

    def extract_dicom_files(self):
        tarchive_path = os.path.join(self.data_dir, self.dicom_archive_obj.tarchive_info_dict["ArchiveLocation"])
        tar = tarfile.open(tarchive_path)
        tar.extractall(path=self.tmp_dir)
        inner_tar_file_name = [f.name for f in tar.getmembers() if f.name.endswith('.tar.gz')][0]
        tar.close()

        inner_tar_path = os.path.join(self.tmp_dir, inner_tar_file_name)
        inner_tar = tarfile.open(inner_tar_path)
        inner_tar.extractall(path=self.tmp_dir)
        inner_tar.close()

        dicom_dir = inner_tar_path.replace(".tar.gz", "")
        return dicom_dir
