
from dataclasses import dataclass
from functools import cached_property

from bids.layout import BIDSFile
from loris_utils.path import remove_path_extension

from loris_bids_reader.info import BidsAcquisitionInfo
from loris_bids_reader.mri.acquisition import MriAcquisition
from loris_bids_reader.mri.sidecar import BidsMriSidecarJsonFile
from loris_bids_reader.reader import BidsDataTypeReader
from loris_bids_reader.utils import find_bids_file_path, get_bids_file_path


@dataclass
class BidsMriDataTypeReader(BidsDataTypeReader):
    @cached_property
    def acquisitions(self) -> list[tuple[MriAcquisition, BidsAcquisitionInfo]]:
        bids_layout = self.session.subject.dataset.layout
        bids_files: list[BIDSFile] = bids_layout.get(  # type: ignore
            subject     = self.session.subject.label,
            session     = self.session.label,
            datatype    = self.name,
            extension   = ['.nii', '.nii.gz'],
        )

        acquisitions: list[tuple[MriAcquisition, BidsAcquisitionInfo]] = []
        for bids_nifti_file in bids_files:
            nifti_path = get_bids_file_path(bids_nifti_file)

            # Get all associated files
            associations: list[BIDSFile] = bids_nifti_file.get_associations()  # type: ignore

            # Find associated files using predicates
            sidecar_path = find_bids_file_path(associations, lambda file: file.entities.get('extension') == '.json')

            bval_path = find_bids_file_path(associations, lambda file: file.entities.get('extension') == '.bval')

            bvec_path = find_bids_file_path(associations, lambda file: file.entities.get('extension') == '.bvec')

            events_path = find_bids_file_path(
                associations,
                lambda file: file.entities.get('suffix') == 'events' and file.entities.get('extension') == '.tsv',
            )

            physio_path = find_bids_file_path(
                associations,
                lambda file: file.entities.get('suffix') in ['physio', 'stim']
                    and file.entities.get('extension') in ['.tsv.gz', '.tsv'],
            )

            sidecar_file = BidsMriSidecarJsonFile(sidecar_path) if sidecar_path is not None else None
            scan_row = self.session.scans_file.get_row(nifti_path) if self.session.scans_file is not None else None
            acquisition_name = remove_path_extension(nifti_path).name

            bids_info = BidsAcquisitionInfo(
                subject         = self.session.subject.label,
                participant_row = self.session.subject.participant_row,
                session         = self.session.label,
                scans_file      = self.session.scans_file,
                data_type       = self.name,
                scan_row        = scan_row,
                name            = acquisition_name,
                suffix          = bids_nifti_file.entities.get('suffix'),
            )

            acquisition = MriAcquisition(
                nifti_path   = nifti_path,
                sidecar_file = sidecar_file,
                bval_path    = bval_path,
                bvec_path    = bvec_path,
                physio_path  = physio_path,
                events_path  = events_path,
            )

            acquisitions.append((acquisition, bids_info))

        return acquisitions
