from pathlib import Path

import pytest
from lib.db.models.physio_channel import DbPhysioChannel
from lib.db.models.physio_channel_type import DbPhysioChannelType
from lib.db.models.physio_file import DbPhysioFile
from lib.env import Env
from loris_bids_utils.eeg.channels import BidsEegChannelsTsvFile, BidsEegChannelTsvRow
from sqlalchemy import select

from loris_bids_importer.channels import get_bids_physio_channel_type, insert_bids_channel


def test_insert_channels_with_missing_and_known_types(env: Env, tmp_path: Path):
    physio_file = DbPhysioFile(
        path=Path('sub-01/eeg/sub-01_eeg.edf'), output_type_id=1, session_id=1,
        inserted_by_user='pytest',
    )
    known_type = DbPhysioChannelType(name='EEG')
    env.db.add_all([physio_file, known_type])
    env.db.flush()

    path = tmp_path / 'channels.tsv'
    path.write_text('name\ttype\tunits\tstatus\nE1\tn/a\tn/a\tN/A\nE2\tEEG\tuV\tn/a\n')
    for row in BidsEegChannelsTsvFile(path).rows:
        insert_bids_channel(env, physio_file, Path('sub-01/eeg/sub-01_channels.tsv'), row, flush=False)
    env.db.flush()
    env.db.expire_all()

    channels = env.db.scalars(select(DbPhysioChannel).order_by(DbPhysioChannel.name)).all()
    assert len(channels) == 2
    assert channels[0].channel_type_id is None
    assert channels[0].channel_type is None
    assert channels[0].status_type_id is None
    assert channels[0].unit is None
    assert channels[1].channel_type_id == known_type.id
    assert channels[1].channel_type is known_type
    assert channels[1].unit == 'uV'
    assert list(env.db.scalars(select(DbPhysioChannelType))) == [known_type]


@pytest.mark.parametrize('channel_type', ['UNKNOWN', 'na', 'NA'])
def test_unregistered_non_missing_types_are_rejected(env: Env, channel_type: str):
    row = BidsEegChannelTsvRow({'name': 'E1', 'type': channel_type, 'units': 'uV'})
    with pytest.raises(Exception, match=f"Unknown channel type '{channel_type}'"):
        get_bids_physio_channel_type(env, row)
