import json
from pathlib import Path

from lib.db.models.bids_dataset import DbBidsDataset
from lib.db.models.bids_file import DbBidsFile
from lib.db.models.physio_coord_system import DbPhysioCoordSystem
from lib.db.models.physio_coord_system_electrode import DbPhysioCoordSystemElectrode
from lib.db.models.physio_coord_system_name import DbPhysioCoordSystemName
from lib.db.models.physio_coord_system_point_3d import DbPhysioCoordSystemPoint3d
from lib.db.models.physio_coord_system_type import DbPhysioCoordSystemType
from lib.db.models.physio_coord_system_unit import DbPhysioCoordSystemUnit
from lib.db.models.physio_electrode import DbPhysioElectrode
from lib.db.models.physio_file import DbPhysioFile
from lib.db.models.physio_modality import DbPhysioModality
from lib.db.models.point_3d import DbPoint3D
from lib.env import Env
from loris_bids_utils.eeg.coord_system import BidsCoordSystemJsonFile
from sqlalchemy import select

from loris_bids_importer.coord_system import (
    get_or_create_bids_electrode_coord_system,
    import_bids_coord_systems,
    link_electrodes_to_coord_system,
)


def test_import_bids_coord_systems_deduplicates_within_bids_file(env: Env, tmp_path: Path):
    _add_lookups(env)
    dataset = _add_dataset(env)
    bids_file = _add_bids_file(env, dataset, Path('sub-01/meg/sub-01_coordsystem.json'))
    first_physio_file = _add_physio_file(env, 1)
    second_physio_file = _add_physio_file(env, 2)
    coord_system_file = _make_coord_system_file(tmp_path, {
        'MEGCoordinateSystem': 'CTF',
        'MEGCoordinateUnits': 'm',
        'HeadCoilCoordinateSystem': 'CTF',
        'HeadCoilCoordinateUnits': 'cm',
        'HeadCoilCoordinates': {'coil1': [1, 2, 3]},
    })

    first = import_bids_coord_systems(env, coord_system_file, bids_file, first_physio_file)
    second = import_bids_coord_systems(env, coord_system_file, bids_file, second_physio_file)
    first_electrode = _add_electrode(env, 101)
    second_electrode = _add_electrode(env, 102)
    link_electrodes_to_coord_system(env, first_physio_file, first['MEG'], [first_electrode])
    link_electrodes_to_coord_system(env, second_physio_file, second['MEG'], [second_electrode])

    assert first.keys() == second.keys()
    assert [item.id for item in first.values()] == [item.id for item in second.values()]
    assert len(env.db.scalars(select(DbPhysioCoordSystem)).all()) == 2
    assert len(env.db.scalars(select(DbPhysioCoordSystemElectrode)).all()) == 2
    assert len(env.db.scalars(select(DbPhysioCoordSystemPoint3d)).all()) == 1
    assert all(item.bids_file_id == bids_file.id for item in first.values())


def test_import_bids_coord_systems_keeps_different_bids_files_separate(env: Env, tmp_path: Path):
    _add_lookups(env)
    dataset = _add_dataset(env)
    first_bids_file = _add_bids_file(env, dataset, Path('sub-01/meg/sub-01_coordsystem.json'))
    second_bids_file = _add_bids_file(env, dataset, Path('sub-02/meg/sub-02_coordsystem.json'))
    first_physio_file = _add_physio_file(env, 1)
    second_physio_file = _add_physio_file(env, 2)
    coord_system_file = _make_coord_system_file(
        tmp_path,
        {'MEGCoordinateSystem': 'CTF', 'MEGCoordinateUnits': 'm'},
    )

    first = import_bids_coord_systems(env, coord_system_file, first_bids_file, first_physio_file)
    second = import_bids_coord_systems(env, coord_system_file, second_bids_file, second_physio_file)

    assert first['MEG'].id != second['MEG'].id
    assert len(env.db.scalars(select(DbPhysioCoordSystem)).all()) == 2


def test_electrode_import_creates_default_coord_system_when_required(env: Env):
    _add_lookups(env)
    physio_file = _add_physio_file(env, 1)

    coord_systems = import_bids_coord_systems(env, None, None, physio_file)

    assert coord_systems == {}

    electrode_system = get_or_create_bids_electrode_coord_system(env, physio_file, None, coord_systems)

    assert electrode_system.name.name == 'Not registered'
    assert electrode_system.type.name == 'Not registered'
    assert electrode_system.unit.name == 'Not registered'


def _make_coord_system_file(tmp_path: Path, metadata: dict[str, object]) -> BidsCoordSystemJsonFile:
    path = tmp_path / 'coordsystem.json'
    path.write_text(json.dumps(metadata))
    return BidsCoordSystemJsonFile(path)


def _add_lookups(env: Env):
    env.db.add_all([
        DbPhysioModality(id=1, name='meg'),
        DbPhysioModality(id=2, name='eeg'),
        DbPhysioModality(id=3, name='ieeg'),
        DbPhysioModality(id=4, name='Not registered'),
        DbPhysioCoordSystemName(id=1, name='Not registered'),
        DbPhysioCoordSystemName(id=2, name='CTF'),
        DbPhysioCoordSystemType(id=1, name='Not registered'),
        DbPhysioCoordSystemType(id=2, name='HeadCoil'),
        DbPhysioCoordSystemType(id=3, name='AnatomicalLandmark'),
        DbPhysioCoordSystemType(id=4, name='DigitizedHeadPoints'),
        DbPhysioCoordSystemType(id=5, name='Fiducials'),
        DbPhysioCoordSystemUnit(id=1, name='Not registered', symbol=None),
        DbPhysioCoordSystemUnit(id=2, name='Meter', symbol='m'),
        DbPhysioCoordSystemUnit(id=3, name='Centimeter', symbol='cm'),
        DbPhysioCoordSystemUnit(id=4, name='Millimeter', symbol='mm'),
    ])
    env.db.flush()


def _add_dataset(env: Env) -> DbBidsDataset:
    dataset = DbBidsDataset(path=Path('bids'))
    env.db.add(dataset)
    env.db.flush()
    return dataset


def _add_bids_file(env: Env, dataset: DbBidsDataset, path: Path) -> DbBidsFile:
    bids_file = DbBidsFile(
        dataset_id   = dataset.id,
        path         = path,
        source_path  = path,
        blake2b_hash = 'hash',
        derivative   = False,
    )
    env.db.add(bids_file)
    env.db.flush()
    return bids_file


def _add_physio_file(env: Env, physio_file_id: int) -> DbPhysioFile:
    physio_file = DbPhysioFile(
        id               = physio_file_id,
        modality_id      = 1,
        output_type_id   = 1,
        session_id       = 1,
        type             = 'ctf',
        inserted_by_user = 'pytest',
        path             = Path(f'file-{physio_file_id}.ds'),
    )
    env.db.add(physio_file)
    env.db.flush()
    return physio_file


def _add_electrode(env: Env, electrode_id: int) -> DbPhysioElectrode:
    point = DbPoint3D(x=float(electrode_id), y=None, z=None)
    env.db.add(point)
    env.db.flush()
    electrode = DbPhysioElectrode(
        id          = electrode_id,
        name        = f'E{electrode_id}',
        point_3d_id = point.id,
        file_path   = Path('electrodes.tsv'),
    )
    env.db.add(electrode)
    env.db.flush()
    return electrode
