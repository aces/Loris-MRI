from dataclasses import dataclass
from pathlib import Path


@dataclass
class BidsImportEnv:
    """
    Information about a specific BIDS import pipeline run.
    """

    data_dir_path: Path
    """
    The LORIS data directory path.
    """

    source_bids_path: Path
    """
    The source BIDS directory path.
    """

    loris_bids_path: Path | None
    """
    The LORIS BIDS directory path for this import, relative to the LORIS data directory.
    """

    total_files_count            : int
    imported_files_count         : int
    ignored_files_count          : int
    failed_files_count           : int
    unknown_mri_scan_types       : list[str]
    unknown_physio_channel_types : list[str]
    unknown_physio_status_types  : list[str]

    def __init__(self, data_dir_path: Path, loris_bids_path: Path | None, total_files_count: int):
        self.data_dir_path                = data_dir_path
        self.loris_bids_path              = loris_bids_path
        self.total_files_count            = total_files_count
        self.imported_files_count         = 0
        self.ignored_files_count          = 0
        self.failed_files_count           = 0
        self.unknown_mri_scan_types       = []
        self.unknown_physio_channel_types = []
        self.unknown_physio_status_types  = []

    @property
    def processed_files_count(self) -> int:
        return self.imported_files_count + self.ignored_files_count + self.failed_files_count

    def register_unknown_mri_scan_type(self, scan_type: str):
        """
        Register an unknown MRI scan type.
        """

        if scan_type not in self.unknown_physio_channel_types:
            self.unknown_physio_channel_types.append(scan_type)

    def register_unknown_physio_channel_type(self, channel_type: str):
        """
        Register an unknown physiological channel type.
        """

        if channel_type not in self.unknown_physio_channel_types:
            self.unknown_physio_channel_types.append(channel_type)

    def register_unknown_physio_status_type(self, status_type: str):
        """
        Register an unknown physiological status type.
        """

        if status_type not in self.unknown_physio_status_types:
            self.unknown_physio_status_types.append(status_type)
