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
