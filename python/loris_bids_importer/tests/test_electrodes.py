from pathlib import Path

from lib.db.models.physio_electrode_material import DbPhysioElectrodeMaterial
from lib.db.models.physio_electrode_type import DbPhysioElectrodeType
from lib.env import Env
from loris_bids_utils.eeg.electrodes import BidsEegElectrodeTsvRow
from sqlalchemy import select

from loris_bids_importer.electrodes import insert_bids_electrode


def test_insert_bids_electrode_uses_typed_orm_models(env: Env):
    row_data: dict[str, str | None] = {
        'name': 'E1',
        'x': '1.5',
        'y': 'n/a',
        'z': '3',
        'type': 'depth',
        'material': 'platinum',
        'impedance': '12',
    }
    electrode = insert_bids_electrode(
        env,
        Path('sub-01/eeg/sub-01_electrodes.tsv'),
        BidsEegElectrodeTsvRow(row_data),
    )

    assert electrode.name == 'E1'
    assert (electrode.point_3d.x, electrode.point_3d.y, electrode.point_3d.z) == (1.5, None, 3.0)
    assert electrode.type is not None
    assert electrode.type.name == 'depth'
    assert electrode.material is not None
    assert electrode.material.name == 'platinum'
    assert electrode.impedance == 12
    assert row_data == {
        'name': 'E1',
        'x': '1.5',
        'y': 'n/a',
        'z': '3',
        'type': 'depth',
        'material': 'platinum',
        'impedance': '12',
    }
    assert len(env.db.scalars(select(DbPhysioElectrodeType)).all()) == 1
    assert len(env.db.scalars(select(DbPhysioElectrodeMaterial)).all()) == 1
