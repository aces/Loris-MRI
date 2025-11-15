from sqlalchemy.orm import Mapped, mapped_column

from lib.db.base import Base


class DbPhysioChannelType(Base):
    __tablename__ = 'physiological_channel_type'

    id                  : Mapped[int]        = mapped_column('PhysiologicalChannelTypeID', primary_key=True)
    channel_type_name   : Mapped[str]        = mapped_column('ChannelTypeName')
    channel_description : Mapped[str | None] = mapped_column('ChannelDescription')
