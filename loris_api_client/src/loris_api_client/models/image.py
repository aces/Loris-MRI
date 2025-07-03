from pydantic import BaseModel, Field


class ImageFile(BaseModel):
    file_name        : str        = Field(alias='Filename')
    output_type      : str        = Field(alias='OutputType')
    acquisition_type : str | None = Field(alias='AcquisitionType')
    is_phantom       : bool       = Field(alias='IsPhantom')


class ImageMeta(BaseModel):
    cand_id     : int = Field(alias='CandID')
    visit_label : str = Field(alias='Visit')


class GetImages(BaseModel):
    meta  : ImageMeta       = Field(alias='Meta')
    files : list[ImageFile] = Field(alias='Files')
