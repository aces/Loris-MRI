from pathlib import Path

from pydantic import BaseModel, ConfigDict, Field

from loris_bids_reader.tsv_file import BIDSTSVFile


class BIDSEventRow(BaseModel):
    """
    Model for a BIDS events TSV file row.

    Documentation: https://bids-specification.readthedocs.io/en/stable/modality-agnostic-files/events.html#events
    """

    model_config = ConfigDict(extra='allow', validate_assignment=True)

    # REQUIRED fields
    onset:         float        = Field(...)
    duration:      float        = Field(..., ge=0)

    # OPTIONAL fields
    trial_type:    str | None   = None
    response_time: float | None = None
    hed:           str | None   = None  # This may be HED in the spec.
    stim_file:     str | None   = None
    channel:       str | None   = None


class BIDSEventsFile(BIDSTSVFile[BIDSEventRow]):
    """
    Wrapper for a BIDS events TSV file.

    Documentation: https://bids-specification.readthedocs.io/en/stable/modality-agnostic-files/events.html#events
    """

    def __init__(self, path: Path):
        super().__init__(BIDSEventRow, path)
