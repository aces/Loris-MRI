from typing import Optional

from sqlalchemy.orm import Mapped, mapped_column

from lib.db.base import Base


class DbMriFileParameter(Base):
    __tablename__ = 'parameter_file'

    id                : Mapped[int]           = mapped_column('ParameterFileID', primary_key=True)
    file_id           : Mapped[int]           = mapped_column('FileID')
    parameter_type_id : Mapped[int]           = mapped_column('ParameterTypeID')
    value             : Mapped[Optional[str]] = mapped_column('Value')
    insert_time       : Mapped[int]           = mapped_column('InsertTime')
