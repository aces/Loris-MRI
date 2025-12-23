from collections.abc import Sequence

from sqlalchemy import select
from sqlalchemy.orm import Session as Database

from lib.db.models.parameter_type import DbParameterType
from lib.db.models.physio_file_parameter import DbPhysioFileParameter


def get_physio_file_parameters(
    db: Database,
    physio_file_id: int,
) -> Sequence[tuple[DbParameterType, DbPhysioFileParameter]]:
    """
    Get the parameters of a physiological file using its ID.
    """

    return db.execute(select(DbParameterType, DbPhysioFileParameter)
        .join(DbPhysioFileParameter.type)
        .where(DbPhysioFileParameter.file_id == physio_file_id)
    ).tuples().all()
