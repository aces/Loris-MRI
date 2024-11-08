from typing import Literal, Optional

from pydantic import BaseModel, Field


class GetDicomArchiveSeries(BaseModel):
    series_description : str                 = Field(alias='SeriesDescription')
    series_number      : int                 = Field(alias='SeriesNumber')
    echo_time          : Optional[str]       = Field(alias='EchoTime')
    repetition_time    : Optional[str]       = Field(alias='RepetitionTime')
    inversion_time     : Optional[str]       = Field(alias='InversionTime')
    slice_thickness    : Optional[str]       = Field(alias='SliceThickness')
    modality           : Literal['MR', 'PT'] = Field(alias='Modality')
    series_uid         : str                 = Field(alias='SeriesUID')


class GetDicomArchive(BaseModel):
    tar_name     : str                         = Field(alias='Tarname')
    patient_name : str                         = Field(alias='Patientname')
    series       : list[GetDicomArchiveSeries] = Field(alias='SeriesInfo')


class GetDicomMeta(BaseModel):
    cand_id     : int = Field(alias='CandID')
    visit_label : str = Field(alias='Visit')


class GetDicom(BaseModel):
    meta : GetDicomMeta          = Field(alias='Meta')
    tars : list[GetDicomArchive] = Field(alias='DicomTars')


class GetDicomProcess(BaseModel):
    end_time  : str = Field(alias='END_TIME')
    exit_code : int = Field(alias='EXIT_CODE')
    id        : int = Field(alias='ID')
    pid       : int = Field(alias='PID')
    progress  : str = Field(alias='PROGRESS')
    state     : str = Field(alias='STATE')


class GetDicomUpload(BaseModel):
    upload_id : int                   = Field(alias='MriUploadID')
    processes : list[GetDicomProcess] = Field(alias='Processes')


class GetDicomProcesses(BaseModel):
    uploads : list[GetDicomUpload] = Field(alias='MriUploads')
