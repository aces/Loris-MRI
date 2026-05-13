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

    imported_acquisitions_count: int = 0
    """
    The number of succesfully imported BIDS acquisitions.
    """

    ignored_acquisitions_count: int = 0
    """
    The number of ignored BIDS acquisition imports.
    """

    failed_acquisitions_count: int = 0
    """
    The number of failed BIDS acquisition imports.
    """

    @property
    def processed_acquisitions_count(self) -> int:
        """
        The total number of processed BIDS acquisitions.
        """

        return self.imported_acquisitions_count + self.ignored_acquisitions_count + self.failed_acquisitions_count
