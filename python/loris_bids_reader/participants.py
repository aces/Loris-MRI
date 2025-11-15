from pathlib import Path
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, field_serializer, field_validator, model_validator

from lib.util.iter import find, replace_or_append
from loris_bids_reader.tsv_file import BIDSTSVFile

Sex        = Literal['male', 'female', 'other']
Handedness = Literal['left', 'right', 'ambidextrous']


class BIDSParticipantRow(BaseModel):
    """
    Model for a BIDS `participants.tsv` file row.

    Documentation: https://bids-specification.readthedocs.io/en/stable/modality-agnostic-files/data-summary-files.html#participants-file
    """

    model_config = ConfigDict(extra='allow', populate_by_name=True)

    # REQUIRED field
    participant_id: str = Field(...)

    # RECOMMENDED fields
    species:     str | None         = None
    age:         int | float | None = None
    sex:         Sex | None         = None
    handedness:  Handedness | None  = None
    strain:      str | int | None   = None
    strain_rrid: str | None         = None

    # OPTIONAL fields
    hed: str | None = Field(None, alias='HED')

    # LORIS fields
    birth_date: str | None = None
    site:       str | None = None
    cohort:     str | None = None
    project:    str | None = None

    @field_validator('participant_id', mode='before')
    @classmethod
    def parse_participant_id(cls, value: Any) -> Any:
        if isinstance(value, str):
            return value.removeprefix('sub-')

        return value

    @field_serializer('participant_id')
    def serialize_participant_id(self, v: str) -> str:
        return f'sub-{v}'

    @model_validator(mode='before')
    @classmethod
    def parse_project(cls, data: Any) -> Any:
        if isinstance(data, dict):
            # Use the deprecated field `subproject` as `cohort` if the latter is not present.
            if 'subproject' in data and 'cohort' not in data:
                data['cohort'] = data['subproject']

        return data  # type: ignore


class BIDSParticipantsFile(BIDSTSVFile[BIDSParticipantRow]):
    """
    Wrapper for a BIDS `participants.tsv` file.

    Documentation: https://bids-specification.readthedocs.io/en/stable/modality-agnostic-files/data-summary-files.html#participants-file
    """

    def __init__(self, path: Path):
        super().__init__(BIDSParticipantRow, path)

    def get(self, participant_id: str) -> BIDSParticipantRow | None:
        return find(lambda row: row.participant_id == participant_id, self.rows)

    def set(self, participant: BIDSParticipantRow):
        replace_or_append(self.rows, lambda row: row.participant_id == participant.participant_id, participant)

    def merge(self, other: 'BIDSParticipantsFile'):
        """
        Copy another `participants.tsv` file into this file. The rows of this file are replaced by
        those of the other file if there are duplicates.
        """

        for other_row in other.rows:
            self.set(other_row)
