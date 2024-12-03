from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from typing import Literal

from lib.db.models.bids_dataset import DbBidsDataset
from lib.env import Env
from loris_bids_utils.reader import BidsDatasetReader


@dataclass
class BidsImporterArgs:
    """
    The CLI arguments given to the BIDS importer.
    """

    source_bids_path: Path
    type: Literal['raw', 'derivative', None]
    bids_validation: bool
    create_candidate: bool
    create_session: bool
    copy: bool
    verbose: bool


@dataclass
class BidsImporter:
    """
    Information about the current BIDS import pipeline run.
    """

    args: BidsImporterArgs
    """
    The CLI arguments given to the BIDS importer.
    """

    data_dir_path: Path
    """
    The LORIS data directory path.
    """

    loris_bids_dataset: DbBidsDataset
    """
    The LORIS BIDS dataset populated by this import.
    """

    module_importers: 'list[Callable[[Env, BidsImporter, BidsDatasetReader], None]]'
    """
    The BIDS importer functions added through module entry points.
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
