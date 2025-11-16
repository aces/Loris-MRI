from dataclasses import dataclass


@dataclass
class BIDSImportEnv:
    """
    Pipeline-specific variables of the BIDS dataset import pipeline.
    """

    data_dir_path         : str
    loris_bids_path       : str | None
    total_files_count     : int
    imported_files_count  : int
    ignored_files_count   : int
    failed_files_count    : int
    unknown_scan_types    : list[str]

    def __init__(self, data_dir_path: str, loris_bids_path: str | None, total_files_count: int):
        self.data_dir_path         = data_dir_path
        self.loris_bids_path       = loris_bids_path
        self.total_files_count     = total_files_count
        self.imported_files_count  = 0
        self.ignored_files_count   = 0
        self.failed_files_count    = 0
        self.unknown_scan_types    = []

    @property
    def processed_files_count(self) -> int:
        return self.imported_files_count + self.ignored_files_count + self.failed_files_count
