from dataclasses import dataclass


@dataclass
class BidsImportEnv:
    """
    Pipeline-specific variables of the BIDS dataset import pipeline.
    """

    data_dir_path         : str
    loris_bids_path       : str
    total_files_count     : int
    imported_files_count  : int
    ignored_files_count   : int
    failed_files_count    : int

    def __init__(self, data_dir_path: str, loris_bids_path: str, total_files_count: int):
        self.data_dir_path         = data_dir_path
        self.loris_bids_path       = loris_bids_path
        self.total_files_count     = total_files_count
        self.imported_files_count  = 0
        self.ignored_files_count   = 0
        self.failed_files_count    = 0

    @property
    def processed_files_count(self) -> int:
        return self.imported_files_count + self.ignored_files_count + self.failed_files_count
