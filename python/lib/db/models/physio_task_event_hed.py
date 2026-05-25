from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.models.hed_schema_node as db_hed_schema_node
import lib.db.models.physio_task_event as db_physio_task_event
import lib.db.models.user as db_user
from lib.db.base import Base
from lib.db.decorators.int_bool import IntBool


class DbPhysioTaskEventHed(Base):
    __tablename__ = 'physiological_task_event_hed_rel'

    id                 : Mapped[int]         = mapped_column('ID', primary_key=True)
    task_event_id      : Mapped[int]         = mapped_column('PhysiologicalTaskEventID', ForeignKey('physiological_task_event.PhysiologicalTaskEventID'))
    hed_tag_id         : Mapped[int | None]  = mapped_column('HEDTagID', ForeignKey('hed_schema_nodes.ID'))
    tag_value          : Mapped[str | None]  = mapped_column('TagValue')
    has_pairing        : Mapped[bool | None] = mapped_column('HasPairing', IntBool, default=False)
    pair_rel_id        : Mapped[int | None]  = mapped_column('PairRelID', ForeignKey('physiological_task_event_hed_rel.ID'))
    additional_members : Mapped[int | None]  = mapped_column('AdditionalMembers', default=0)
    tagger_id          : Mapped[int | None]  = mapped_column('TaggedBy', ForeignKey('users.ID'))

    task_event      : Mapped['db_physio_task_event.DbPhysioTaskEvent'] = relationship('DbPhysioTaskEvent')
    hed_schema_node : Mapped['db_hed_schema_node.DbHedSchemaNode']     = relationship('DbHedSchemaNode')
    tagger          : Mapped['db_user.DbUser']                         = relationship('DbUser')
