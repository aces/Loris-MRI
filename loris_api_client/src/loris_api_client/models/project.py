from pydantic import BaseModel, Field


class ProjectImage(BaseModel):
    cand_id     : str = Field(alias='Candidate')
    psc_id      : str = Field(alias='PSCID')
    visit_label : str = Field(alias='Visit')
    visit_date  : str = Field(alias='Visit_date')
    site        : str = Field(alias='Site')
    scan_type   : str = Field(alias='ScanType')
    qc_qstatus  : str = Field(alias='QC_status')
    selected    : str = Field(alias='Selected')
    link        : str = Field(alias='Link')
    insert_time : str = Field(alias='InsertTime')


class ProjectInstrument(BaseModel):
    full_name        : str       = Field(alias='Fullname')
    subgoup_name     : str       = Field(alias='Subgroup')
    dde_enabled      : bool      = Field(alias='DoubleDataEntryEnabled')
    dde_visit_labels : list[str] = Field(alias='DoubleDataEntryVisits')


class ProjectMeta(BaseModel):
    name : str  = Field(alias='Project')


class ProjectRecording(BaseModel):
    cand_id     : str = Field(alias='Candidate')
    psc_id      : str = Field(alias='PSCID')
    visit_label : str = Field(alias='Visit')
    visit_date  : str = Field(alias='Visit_date')
    site_name   : str = Field(alias='Site')
    file        : str = Field(alias='File')
    modality    : str = Field(alias='Modality')
    insert_time : str = Field(alias='InsertTime')
    link        : str = Field(alias='Link')


class GetProject(BaseModel):
    meta             : ProjectMeta = Field(alias='Meta')
    cand_ids         : list[str]   = Field(alias='Candidates')
    instrument_names : list[str]   = Field(alias='Instruments')
    visit_labels     : list[str]   = Field(alias='Visits')


class GetProjectCandidates(BaseModel):
    meta     : ProjectMeta = Field(alias='Meta')
    cand_ids : list[str]   = Field(alias='Candidates')


class GetProjectImages(BaseModel):
    meta   : ProjectMeta        = Field(alias='Meta')
    images : list[ProjectImage] = Field(alias='Images')


class GetProjectInstruments(BaseModel):
    meta        : ProjectMeta             = Field(alias='Meta')
    instruments : list[ProjectInstrument] = Field(alias='Instruments')


class GetProjectVisits(BaseModel):
    meta         : ProjectMeta = Field(alias='Meta')
    visit_labels : list[str]   = Field(alias='Visits')


class GetProjectRecordings(BaseModel):
    meta       : ProjectMeta            = Field(alias='Meta')
    recordings : list[ProjectRecording] = Field(alias='Recordings')
