from typing import Literal, Optional

from pydantic import BaseModel, Field


class DicomArchiveSeries(BaseModel):
    series_description : str                 = Field(alias='SeriesDescription')
    series_number      : int                 = Field(alias='SeriesNumber')
    echo_time          : Optional[str]       = Field(alias='EchoTime')
    repetition_time    : Optional[str]       = Field(alias='RepetitionTime')
    inversion_time     : Optional[str]       = Field(alias='InversionTime')
    slice_thickness    : Optional[str]       = Field(alias='SliceThickness')
    modality           : Literal['MR', 'PT'] = Field(alias='Modality')
    series_uid         : str                 = Field(alias='SeriesUID')


class DicomArchive(BaseModel):
    tar_name     : str                         = Field(alias='Tarname')
    patient_name : str                         = Field(alias='Patientname')
    series       : list[DicomArchiveSeries] = Field(alias='SeriesInfo')


class DicomMeta(BaseModel):
    cand_id     : int = Field(alias='CandID')
    visit_label : str = Field(alias='Visit')


class GetDicom(BaseModel):
    meta : DicomMeta          = Field(alias='Meta')
    tars : list[DicomArchive] = Field(alias='DicomTars')


class GetDicomProcess(BaseModel):
    end_time  : Optional[str] = Field(alias='END_TIME')
    exit_code : Optional[int] = Field(alias='EXIT_CODE')
    id        : int           = Field(alias='ID')
    pid       : int           = Field(alias='PID')
    progress  : str           = Field(alias='PROGRESS')
    state     : str           = Field(alias='STATE')


class DicomUpload(BaseModel):
    upload_id : int                   = Field(alias='MriUploadID')
    processes : list[GetDicomProcess] = Field(alias='Processes')


class PostDicomProcesses(BaseModel):
    link      : str                   = Field(alias='Link')
    processes : list[GetDicomProcess] = Field(alias='ProcessState')


class GetDicomProcesses(BaseModel):
    uploads : list[DicomUpload] = Field(alias='MriUploads')
