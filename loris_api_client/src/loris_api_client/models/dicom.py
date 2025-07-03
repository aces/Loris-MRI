from typing import Literal

from pydantic import BaseModel, Field


class DicomArchiveSeries(BaseModel):
    series_description : str                 = Field(alias='SeriesDescription')
    series_number      : int                 = Field(alias='SeriesNumber')
    echo_time          : str | None          = Field(alias='EchoTime')
    repetition_time    : str | None          = Field(alias='RepetitionTime')
    inversion_time     : str | None          = Field(alias='InversionTime')
    slice_thickness    : str | None          = Field(alias='SliceThickness')
    modality           : Literal['MR', 'PT'] = Field(alias='Modality')
    series_uid         : str                 = Field(alias='SeriesUID')


class DicomArchive(BaseModel):
    tar_name     : str                      = Field(alias='Tarname')
    patient_name : str                      = Field(alias='Patientname')
    series       : list[DicomArchiveSeries] = Field(alias='SeriesInfo')


class DicomMeta(BaseModel):
    cand_id     : int = Field(alias='CandID')
    visit_label : str = Field(alias='Visit')


class GetDicom(BaseModel):
    meta : DicomMeta          = Field(alias='Meta')
    tars : list[DicomArchive] = Field(alias='DicomTars')
