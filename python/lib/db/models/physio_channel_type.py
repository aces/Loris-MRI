from sqlalchemy.orm import Mapped, mapped_column

from lib.db.base import Base


class DbPhysioChannelType(Base):
    __tablename__ = 'physiological_channel_type'

    id          : Mapped[int]        = mapped_column('PhysiologicalChannelTypeID', primary_key=True)
    name        : Mapped[str]        = mapped_column('ChannelTypeName')
    description : Mapped[str | None] = mapped_column('ChannelDescription')
