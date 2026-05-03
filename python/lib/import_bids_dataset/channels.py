from pathlib import Path

from loris_bids_reader.eeg.channels import BidsEegChannelsTsvFile, BidsEegChannelTsvRow
from loris_bids_reader.info import BidsAcquisitionInfo
from loris_utils.crypto import compute_file_blake2b_hash
from loris_utils.error import group_errors, group_errors_tuple

from lib.db.models.physio_channel_type import DbPhysioChannelType
from lib.db.models.physio_file import DbPhysioFile
from lib.db.models.physio_status_type import DbPhysioStatusType
from lib.db.models.session import DbSession
from lib.db.queries.physio_channel import try_get_channel_type_with_name, try_get_status_type_with_name
from lib.env import Env
from lib.import_bids_dataset.copy_files import get_loris_bids_file_path
from lib.import_bids_dataset.env import BidsImportEnv
from lib.physio.channels import insert_physio_channel
from lib.physio.parameters import insert_physio_file_parameter


def insert_bids_channels_file(
    env: Env,
    import_env: BidsImportEnv,
    physio_file: DbPhysioFile,
    session: DbSession,
    acquisition: BidsAcquisitionInfo,
    channels_file: BidsEegChannelsTsvFile,
) -> Path:
    """
    Insert the channels from a BIDS channels file into the database.
    """

    loris_channels_file_path = get_loris_bids_file_path(
        import_env, session, acquisition.data_type, channels_file.path
    )

    blake2_hash = compute_file_blake2b_hash(channels_file.path)

    group_errors(
        f"Could not import channels from file '{channels_file.path.name}'.",
        (
            lambda: insert_bids_channel(
                env,
                physio_file,
                loris_channels_file_path,
                channel,
                flush=False,
            ) for channel in channels_file.rows
        ),
    )

    insert_physio_file_parameter(env, physio_file, 'channel_file_blake2b_hash', blake2_hash)

    env.db.flush()

    return loris_channels_file_path


def insert_bids_channel(
    env: Env,
    physio_file: DbPhysioFile,
    loris_channels_file_path: Path,
    channel: BidsEegChannelTsvRow,
    flush: bool = True,
):
    """
    Insert a channel from a BIDS channels file into the database.
    """

    channel_type, status_type = group_errors_tuple(
        f"Could not import channel '{channel.name}'.",
        lambda: get_bids_physio_channel_type(env, channel),
        lambda: get_bids_physio_status_type(env, channel),
    )

    insert_physio_channel(
        env,
        physio_file,
        channel_type,
        status_type,
        loris_channels_file_path,
        channel.name,
        channel.description,
        int(channel.sampling_frequency) if channel.sampling_frequency is not None else None,
        channel.low_cutoff,
        channel.high_cutoff,
        channel.manual,
        int(channel.notch) if channel.notch is not None else None,
        channel.status_description,
        channel.unit,
        channel.reference,
        flush=flush,
    )


def get_bids_physio_channel_type(
    env: Env,
    channel: BidsEegChannelTsvRow,
) -> DbPhysioChannelType:
    """
    Get a physiological channel type from the database using a BIDS channel TSV row, or raise an
    exception if that channel type is not found in the database.
    """

    channel_type = try_get_channel_type_with_name(env.db, channel.type)
    if channel_type is not None:
        return channel_type

    raise Exception(f"Unknown channel type '{channel.type}'.")


def get_bids_physio_status_type(
    env: Env,
    channel: BidsEegChannelTsvRow,
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

    raise Exception(f"Unknown channel status type '{channel.status}'.")
