from typing import Any

from pydantic import BaseModel, Field, field_validator


class VisitMeta(BaseModel):
    cand_id : str = Field(alias='CandID')
    visit   : str = Field(alias='Visit')
    site    : str = Field(alias='Site')
    project : str = Field(alias='Project')
    cohort  : str = Field(alias='Cohort')


class VisitStage(BaseModel):
    date  : str = Field(alias='Date')
    status: str = Field(alias='Status')


class GetVisit(BaseModel):
    meta   : VisitMeta             = Field(alias='Meta')
    stages : dict[str, VisitStage] = Field(alias='Stages')

    @field_validator('stages', mode='before', check_fields=True)
    @classmethod
    def empty_dict(cls: type['GetVisit'], v: Any) -> dict[str, VisitStage]:  # ruff: ignore
        if v == []:
            return {}

        return v
