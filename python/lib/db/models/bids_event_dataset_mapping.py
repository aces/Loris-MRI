from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column

from lib.db.base import Base
from lib.db.decorators.int_bool import IntBool


class DbBidsEventDatasetMapping(Base):
    __tablename__ = 'bids_event_dataset_mapping'

    id                 : Mapped[int]         = mapped_column('ID', primary_key=True)
    project_id         : Mapped[int]         = mapped_column('ProjectID', ForeignKey('Project.ProjectID'))
    property_name      : Mapped[str]         = mapped_column('PropertyName')
    property_value     : Mapped[str]         = mapped_column('PropertyValue')
    hed_tag_id         : Mapped[int | None]  = mapped_column('HEDTagID', ForeignKey('hed_schema_nodes.ID'))
    tag_value          : Mapped[str | None]  = mapped_column('TagValue')
    description        : Mapped[str | None]  = mapped_column('Description')
    has_pairing        : Mapped[bool | None] = mapped_column('HasPairing', IntBool)
    pair_rel_id        : Mapped[int | None]  = mapped_column('PairRelID')
    additional_members : Mapped[int | None]  = mapped_column('AdditionalMembers')
    tagged_by          : Mapped[int | None]  = mapped_column('TaggedBy', ForeignKey('users.ID'))
