from pydantic import BaseModel, Field


class CandidateMeta(BaseModel):
    cand_id : str  = Field(alias='CandID')
    psc_id  : str  = Field(alias='PSCID')
    project : str  = Field(alias='Project')
    site    : str  = Field(alias='Site')
    dob     : str  = Field(alias='DoB')
    sex     : str  = Field(alias='Sex')


class GetCandidate(BaseModel):
    meta         : CandidateMeta = Field(alias='Meta')
    visit_labels : list[str]     = Field(alias='Visits')
