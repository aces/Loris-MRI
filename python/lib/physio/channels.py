from datetime import datetime
from decimal import Decimal
from pathlib import Path

from lib.db.models.physio_channel import DbPhysioChannel
from lib.db.models.physio_channel_type import DbPhysioChannelType
from lib.db.models.physio_file import DbPhysioFile
from lib.db.models.physio_status_type import DbPhysioStatusType
from lib.env import Env


def insert_physio_channel(
    env: Env,
    physio_file: DbPhysioFile,
    channel_type: DbPhysioChannelType,
    status_type: DbPhysioStatusType | None,
    file_path: Path,
    name: str,
    description: str | None,
    sampling_frequency: int | None,
    low_cutoff: Decimal | None,
    high_cutoff: Decimal | None,
    notch: int | None,
    status_description: str | None,
    unit: str | None,
) -> DbPhysioChannel:
    """
    Insert a physiological channel into the database.
    """

    event_file = DbPhysioChannel(
        physio_file_id     = physio_file.id,
        file_path          = file_path,
        channel_type_id    = channel_type.id,
        status_type_id     = status_type.id if status_type is not None else None,
        insert_time        = datetime.now(),
        name               = name,
        description        = description,
        sampling_frequency = sampling_frequency,
        low_cutoff         = low_cutoff,
        high_cutoff        = high_cutoff,
        manual_flag        = None,  # TODO
        notch              = notch,  # TODO
        reference          = None,  # TODO
        status_description = status_description,
        unit               = unit,
    )

    env.db.add(event_file)
    env.db.flush()

    return event_file
