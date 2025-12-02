from pathlib import Path

from pydantic import BaseModel, ConfigDict, Field

from loris_bids_reader.tsv_file import BIDSJSONFile


class BIDSContainer(BaseModel):
    type: str | None = None
    tag:  str | None = None
    uri:  str | None = None


class BIDSGeneratedByItem(BaseModel):
    name:        str                  = Field(alias='Name')
    version:     str | None           = Field(None, alias='Version')
    description: str | None           = Field(None, alias='Description')
    code_url:    str | None           = Field(None, alias='CodeURL')
    container:   BIDSContainer | None = Field(None, alias='Container')


class BIDSSourceDataset(BaseModel):
    url:     str | None = Field(None, alias='URL')
    doi:     str | None = Field(None, alias='DOI')
    version: str | None = Field(None, alias='Version')


class BIDSDatasetDescription(BaseModel):
    """
    Model for a BIDS `dataset_description.json` file.

    Documentation: https://bids-specification.readthedocs.io/en/stable/modality-agnostic-files/dataset-description.html#dataset_descriptionjson
    """

    model_config = ConfigDict(extra='allow', populate_by_name=True)

    name:                 str                              = Field(alias='Name')
    bids_version:         str                              = Field(alias='BIDSVersion')
    hed_version:          str | list[str] | None           = Field(None, alias='HEDVersion')
    dataset_links:        dict[str, str] | None            = Field(None, alias='DatasetLinks')
    dataset_type:         str | None                       = Field(None, alias='DatasetType')
    license:              str | None                       = Field(None, alias='License')
    authors:              list[str] | None                 = Field(None, alias='Authors')
    keywords:             list[str] | None                 = Field(None, alias='Keywords')
    acknowledgements:     str | None                       = Field(None, alias='Acknowledgements')
    how_to_acknowledge:   str | None                       = Field(None, alias='HowToAcknowledge')
    funding:              list[str] | None                 = Field(None, alias='Funding')
    ethics_approvals:     list[str] | None                 = Field(None, alias='EthicsApprovals')
    references_and_links: list[str] | None                 = Field(None, alias='ReferencesAndLinks')
    dataset_doi:          str | None                       = Field(None, alias='DatasetDOI')
    generated_by:         list[BIDSGeneratedByItem] | None = Field(None, alias='GeneratedBy')
    source_datasets:      list[BIDSSourceDataset] | None   = Field(None, alias='SourceDatasets')


class BIDSDatasetDescriptionFile(BIDSJSONFile[BIDSDatasetDescription]):
    """
    Wrapper for a BIDS `dataset_description.json` file.

    Documentation: https://bids-specification.readthedocs.io/en/stable/modality-agnostic-files/dataset-description.html#dataset_descriptionjson
    """

    def __init__(self, path: Path):
        super().__init__(BIDSDatasetDescription, path)
