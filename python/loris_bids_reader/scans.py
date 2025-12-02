from datetime import datetime
from pathlib import Path
from typing import Any, Literal

import dateutil.parser
from dateutil.parser import ParserError
from pydantic import BaseModel, ConfigDict, Field, model_validator

from lib.util.iter import find, replace_or_append
from loris_bids_reader.tsv_file import BIDSTSVFile

Sex        = Literal['male', 'female', 'other']
Handedness = Literal['left', 'right', 'ambidextrous']


class BIDSScanRow(BaseModel):
    """
    Model for a BIDS `scans.tsv` file row.

    Documentation: https://bids-specification.readthedocs.io/en/stable/modality-agnostic-files/data-summary-files.html#scans-file
    """

    model_config = ConfigDict(extra='allow', populate_by_name=True)

    # REQUIRED field
    filename: str = Field(...)

    # OPTIONAL fields
    acq_time: str | None = None
    hed:      str | None = Field(None, alias='HED')

    # LORIS-specific fields
    age_at_scan:  str | None = None
    mri_acq_time: str | None = None
    eeg_acq_time: str | None = None

    age_at_scan:  str | None

    def get_acquisition_time(self) -> datetime | None:
        """
        Read the acquisition time field of a scan from this `scans.tsv` row.
        """

        for acq_time in [self.acq_time, self.mri_acq_time, self.eeg_acq_time]:
            if acq_time is not None:
                try:
                    return dateutil.parser.parse(acq_time)
                except ParserError:
                    pass

        return None

    @model_validator(mode='before')
    @classmethod
    def parse_age_at_scan(cls, data: Any) -> Any:
        for key in ['age', 'age_acq_time']:
            # Use the fields `age` and `age_acq_time` as `age_at_scan` if the latter is not present.
            if key in data and 'age_at_scan' not in data:
                data['age_at_scan'] = data[key]

        return data


class BIDSScansFile(BIDSTSVFile[BIDSScanRow]):
    """
    Wrapper for a BIDS `scans.tsv` file.

    Documentation: https://bids-specification.readthedocs.io/en/stable/modality-agnostic-files/data-summary-files.html#scans-file
    """

    def __init__(self, path: Path):
        super().__init__(BIDSScanRow, path)

    def get(self, filename: str) -> BIDSScanRow | None:
        return find(lambda row: row.filename == filename, self.rows)

    def set(self, scan: BIDSScanRow):
        replace_or_append(self.rows, lambda row: row.filename == scan.filename, scan)

    def merge(self, other: 'BIDSScansFile'):
        """
        Copy another `scans.tsv` file into this file. The rows of this file are replaced by
        those of the other file if there are duplicates.
        """

        for other_row in other.rows:
            self.set(other_row)
