from sqlalchemy.orm import Mapped, mapped_column

from lib.db.base import Base


class DbPhysioStatusType(Base):
    __tablename__ = 'physiological_status_type'

    id             : Mapped[int] = mapped_column('PhysiologicalStatusTypeID', primary_key=True)
    channel_status : Mapped[str] = mapped_column('ChannelStatus')
