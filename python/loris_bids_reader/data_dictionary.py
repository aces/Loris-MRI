from pathlib import Path

from pydantic import BaseModel, ConfigDict, Field, RootModel

from loris_bids_reader.json_file import BIDSJSONFile


class BIDSLevelDescription(BaseModel):
    """Model for a level item within a categorical column description."""

    model_config = ConfigDict(populate_by_name=True)

    description: str = Field(alias='Description')
    term_url:    str | None = Field(None, alias='TermURL')


class BIDSFieldDescription(BaseModel):
    """Model for a single column description in a BIDS data dictionary."""

    model_config = ConfigDict(populate_by_name=True)

    long_name:   str | None                                  = Field(None, alias='LongName')
    description: str | None                                  = Field(None, alias='Description')
    format:      str | None                                  = Field(None, alias='Format')
    levels:      dict[str, str | BIDSLevelDescription] | None = Field(None, alias='Levels')
    units:       str | None                                  = Field(None, alias='Units')
    delimiter:   str | None                                  = Field(None, alias='Delimiter')
    term_url:    str | None                                  = Field(None, alias='TermURL')
    hed:         str | dict[str, str] | None                 = Field(None, alias='HED')
    maximum:     float | int | None                          = Field(None, alias='Maximum')
    minimum:     float | int | None                          = Field(None, alias='Minimum')


class BIDSDataDict(RootModel[dict[str, BIDSFieldDescription]]):
    """
    Model for a BIDS data dictionary JSON file (sidecar for TSV files).

    Documentation: https://bids-specification.readthedocs.io/en/stable/common-principles.html#tabular-files
    """


class BIDSDataDictFile(BIDSJSONFile[BIDSDataDict]):
    """
    Wrapper for a BIDS data dictionary JSON file (sidecar for TSV files).

    Documentation: https://bids-specification.readthedocs.io/en/stable/common-principles.html#tabular-files
    """

    def __init__(self, path: Path):
        super().__init__(BIDSDataDict, path)
