from sqlalchemy.orm import Mapped, mapped_column

from lib.db.base import Base


class DbBidsPhaseEncodingDirection(Base):
    __tablename__ = 'bids_phase_encoding_direction'

    id   : Mapped[int] = mapped_column('BIDSPhaseEncodingDirectionID', primary_key=True)
    name : Mapped[str] = mapped_column('BIDSPhaseEncodingDirectionName')
