from decimal import Decimal
from pathlib import Path

from lib.db.models.physio_channel_type import DbPhysioChannelType
from lib.db.models.physio_file import DbPhysioFile
from lib.db.models.physio_status_type import DbPhysioStatusType
from lib.db.models.session import DbSession
from lib.db.queries.physio_channel import try_get_channel_type_with_name, try_get_status_type_with_name
from lib.env import Env
from lib.import_bids_dataset.copy_files import get_loris_file_path
from lib.import_bids_dataset.env import BidsImportEnv
from lib.physio.channels import insert_physio_channel
from lib.util.error import group_errors, group_errors_tuple
from loris_bids_reader.dataset import BIDSAcquisition, BIDSDataType
from loris_bids_reader.meg.channels import BIDSMEGChannelRow, BIDSMEGChannelsFile


def insert_bids_channels_file(
    env: Env,
    import_env: BidsImportEnv,
    physio_file: DbPhysioFile,
    session: DbSession,
    acquisition: BIDSAcquisition[BIDSDataType],
    channels_file: BIDSMEGChannelsFile,
):
    """
    Insert the channels from a BIDS channels file into the database.
    """

    loris_channels_file_path = get_loris_file_path(import_env, session, acquisition, channels_file.path)
    group_errors(
        f"Could not import channels from file '{channels_file.path.name}'.",
        (
            lambda: insert_bids_channel(
                env,
                import_env,
                physio_file,
                loris_channels_file_path,
                channel,
            ) for channel in channels_file.rows
        ),
    )


def insert_bids_channel(
    env: Env,
    import_env: BidsImportEnv,
    physio_file: DbPhysioFile,
    loris_channels_file_path: Path,
    channel: BIDSMEGChannelRow,
):
    """
    Insert a channel from a BIDS channels file into the database.
    """

    channel_type, status_type = group_errors_tuple(
        f"Could not import channel '{channel.name}'.",
        lambda: get_bids_physio_channel_type(env, import_env, channel),
        lambda: get_bids_physio_status_type(env, import_env, channel),
    )

    physio_channel = insert_physio_channel(
        env,
        physio_file,
        channel_type,
        status_type,
        loris_channels_file_path,
        channel.name,
        channel.description,
        int(channel.sampling_frequency) if channel.sampling_frequency is not None else None,
        Decimal(channel.low_cutoff) if channel.low_cutoff is not None else None,
        Decimal(channel.high_cutoff) if channel.high_cutoff is not None else None,
        int(channel.notch) if isinstance(channel.notch, float) else None,
        channel.status_description,
        channel.units,
    )

    print(f"DEBUG: Channel inserted with ID {physio_channel.id}")


def get_bids_physio_channel_type(
    env: Env,
    import_env: BidsImportEnv,
    channel: BIDSMEGChannelRow,
) -> DbPhysioChannelType:
    """
    Get a physiological channel type from the database using a BIDS channel TSV row, or raise an
    exception if that channel type is not found in the database.
    """

    channel_type = try_get_channel_type_with_name(env.db, channel.type)
    if channel_type is not None:
        return channel_type

    import_env.register_unknown_physio_channel_type(channel.type)

    raise Exception(f"Unknown channel type '{channel.type}'.")


def get_bids_physio_status_type(
    env: Env,
    import_env: BidsImportEnv,
    channel: BIDSMEGChannelRow,
) -> DbPhysioStatusType | None:
    """
    Get a physiological status type from the database using a BIDS channel TSV row, or raise an
    exception if that status type is not found in the database.
    """

    if channel.status is None:
        return None

    status_type = try_get_status_type_with_name(env.db, channel.status)
    if status_type is not None:
        return status_type

    import_env.register_unknown_physio_status_type(channel.status)

    raise Exception(f"Unknown channel status type '{channel.status}'.")
