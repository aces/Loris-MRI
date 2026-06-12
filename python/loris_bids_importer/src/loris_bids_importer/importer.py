from dataclasses import dataclass
from pathlib import Path
from typing import Literal


@dataclass
class BidsImporterArgs:
    """
    The arguments given to the BIDS importer.
    """

    source_bids_path: Path
    """
    The path of the source BIDS dataset to import.
    """

    type: Literal['raw', 'derivative', None]
    """
    The type of the BIDS dataset to import.
    """

    bids_validation: bool
    """
    Whether to validate the BIDS dataset.
    """

    create_candidate: bool
    """
    Whether to create candidates in LORIS.
    """

    create_session: bool
    """
    Whether to create sessions in LORIS.
    """

    copy: bool
    """
    Whether to copy the BIDS dataset into the LORIS data directory.
    """

    verbose: bool
    """
    Whether to enable verbose output.
    """


@dataclass
class BidsImporter:
    """
    Information about the current BIDS importer run.
    """

    args: BidsImporterArgs
    """
    The arguments given to the BIDS importer.
    """

    data_dir_path: Path
    """
    The LORIS data directory path.
    """

    loris_bids_path: Path | None
    """
    The LORIS BIDS directory path for this import, relative to the LORIS data directory.
    """

    files_dict: dict[Path, Path]
    """
    A dictionary mapping the original BIDS file paths to their corresponding paths in the LORIS data
    directory. Both paths are relative to their respective BIDS dataset root directories.
    """

    imported_acquisitions_count: int = 0
    """
    The number of successfully imported BIDS acquisitions.
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
