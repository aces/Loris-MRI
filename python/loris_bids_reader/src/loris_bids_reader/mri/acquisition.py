from dataclasses import dataclass
from pathlib import Path

from loris_bids_reader.mri.sidecar import BidsMriSidecarJsonFile


@dataclass
class MriAcquisition:
    """
    An MRI acquisition and its related files.
    """

    nifti_path: Path
    """
    The main NIfTI file path.
    """

    sidecar_file: BidsMriSidecarJsonFile | None
    """
    The related JSON sidecar file path, if it exists.
    """

    bval_path: Path | None
    """
    The related bval file path, if it exists.
    """

    bvec_path: Path | None
    """
    The related bvec file path, if it exists.
    """

    physio_path: Path | None
    """
    The related physio file path, if it exists.
    """

    events_path: Path | None
    """
    The related events file path, if it exists.
    """
