from lib.db.models.bids_file import DbBidsFile
from lib.db.models.physio_coord_system import DbPhysioCoordSystem
from lib.db.models.physio_file import DbPhysioFile
from lib.db.models.physio_modality import DbPhysioModality
from lib.env import Env
from lib.physio.coord_system import (
    get_coord_system_name,
    get_coord_system_type,
    get_coord_system_unit,
    get_or_create_coord_system,
    get_or_create_electrode_relation,
    get_or_create_point,
    get_or_create_point_relation,
    get_physio_modality,
)
from loris_bids_utils.eeg.coord_system import BidsCoordSystem, BidsCoordSystemJsonFile
from loris_utils.iter import find


def import_bids_coord_systems(
    env: Env,
    file: BidsCoordSystemJsonFile | None,
    bids_file: DbBidsFile | None,
    physio_file: DbPhysioFile,
    electrode_ids: list[int],
) -> list[DbPhysioCoordSystem]:
    """
    Import the coordinate systems described by a BIDS coordinate system file.
    """

    if physio_file.modality is not None:
        default_modality = physio_file.modality
    else:
        default_modality = get_physio_modality(env, 'Not registered')

    if file is not None:
        definitions = file.get_coord_systems()
    else:
        definitions = []

    # An electrodes.tsv file in a MEG dataset can describe simultaneously recorded EEG electrodes.
    has_eeg_coord_system = find(definitions, lambda definition: definition.kind == 'EEG') is not None
    if default_modality.name == 'meg' and has_eeg_coord_system:
        electrode_kind = 'EEG'
    else:
        electrode_kind = find(['MEG', 'EEG', 'iEEG'], lambda kind: kind.lower() == default_modality.name)

    db_coord_systems: list[DbPhysioCoordSystem] = []
    for definition in definitions:
        db_coord_systems.append(import_bids_coord_system(
            env,
            physio_file,
            bids_file,
            definition,
            default_modality,
            electrode_kind,
            electrode_ids,
        ))

    if not any(definition.kind == electrode_kind for definition in definitions):
        coord_system = get_or_create_coord_system(
            env,
            bids_file,
            default_modality,
            get_coord_system_type(env, 'Not registered'),
            get_coord_system_name(env, 'Not registered'),
            get_coord_system_unit(env, None),
        )

        for electrode_id in electrode_ids:
            get_or_create_electrode_relation(env, coord_system, electrode_id, physio_file)

        db_coord_systems.insert(0, coord_system)

    env.db.flush()
    return db_coord_systems


def import_bids_coord_system(
    env: Env,
    physio_file: DbPhysioFile,
    bids_file: DbBidsFile | None,
    coord_system: BidsCoordSystem,
    default_modality: DbPhysioModality,
    electrode_kind: str | None,
    electrode_ids: list[int],
) -> DbPhysioCoordSystem:
    """
    Import a BIDS coordinate system into LORIS.
    """

    is_sensor = coord_system.kind in ['MEG', 'EEG', 'iEEG']
    if is_sensor:
        modality_name = coord_system.kind.lower()
    else:
        modality_name = default_modality.name

    modality = get_physio_modality(env, modality_name)

    coord_type = get_coord_system_type(env, 'Not registered' if is_sensor else coord_system.kind)
    coord_name = get_coord_system_name(env, coord_system.name)
    coord_unit = get_coord_system_unit(env, coord_system.unit)

    db_coord_system = get_or_create_coord_system(
        env,
        bids_file,
        modality,
        coord_type,
        coord_name,
        coord_unit,
    )

    for point_name, coordinates in coord_system.points.items():
        point = get_or_create_point(env, *coordinates)
        get_or_create_point_relation(env, db_coord_system, point, point_name)

    if coord_system.kind == electrode_kind:
        for electrode_id in electrode_ids:
            get_or_create_electrode_relation(env, db_coord_system, electrode_id, physio_file)

    return db_coord_system
