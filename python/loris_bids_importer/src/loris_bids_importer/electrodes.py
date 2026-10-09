from pathlib import Path

from lib.db.models.physio_coord_system import DbPhysioCoordSystem
from lib.db.models.physio_electrode import DbPhysioElectrode
from lib.db.models.physio_file import DbPhysioFile
from lib.db.models.session import DbSession
from lib.env import Env
from lib.physio.electrodes import (
    get_or_create_electrode_material,
    get_or_create_electrode_type,
    insert_physio_electrode,
)
from lib.physio.parameters import register_physio_file_parameter
from loris_bids_utils.eeg.electrodes import BidsEegElectrodesTsvFile, BidsEegElectrodeTsvRow
from loris_bids_utils.info import BidsAcquisitionInfo
from loris_utils.crypto import compute_file_blake2b_hash
from loris_utils.error import group_errors

from loris_bids_importer.coord_system import link_electrodes_to_coord_system
from loris_bids_importer.copy_files import get_loris_bids_file_path
from loris_bids_importer.dataset import get_or_create_loris_bids_file
from loris_bids_importer.importer import BidsImporter


def insert_bids_electrodes_file(
    env: Env,
    importer: BidsImporter,
    physio_file: DbPhysioFile,
    session: DbSession,
    acquisition: BidsAcquisitionInfo,
    electrodes_file: BidsEegElectrodesTsvFile,
    coord_system: DbPhysioCoordSystem,
    derivative: bool = False,
) -> Path:
    """
    Insert the electrodes from a BIDS electrode file and link them to their coordinate system.
    """

    loris_electrodes_file_path = get_loris_bids_file_path(
        importer,
        session,
        acquisition.data_type,
        electrodes_file.path,
        derivative,
    )

    blake2_hash = compute_file_blake2b_hash(electrodes_file.path)

    electrodes = group_errors(
        f"Could not import electrodes from file '{electrodes_file.path.name}'.",
        (
            lambda: insert_bids_electrode(
                env,
                loris_electrodes_file_path,
                electrode,
                flush=False,
            ) for electrode in electrodes_file.rows
        ),
    )

    env.db.flush()

    link_electrodes_to_coord_system(env, physio_file, coord_system, electrodes)
    get_or_create_loris_bids_file(
        env,
        importer,
        electrodes_file.path,
        loris_electrodes_file_path,
    )
    register_physio_file_parameter(
        env,
        physio_file,
        'electrode_file_blake2b_hash',
        blake2_hash,
    )

    env.db.flush()

    return loris_electrodes_file_path


def insert_bids_electrode(
    env: Env,
    loris_file_path: Path,
    electrode: BidsEegElectrodeTsvRow,
    flush: bool = True,
) -> DbPhysioElectrode:
    """
    Insert an electrode from a BIDS electrode TSV row into the database.
    """

    electrode_type = get_or_create_electrode_type(env, electrode.type) if electrode.type is not None else None

    material = get_or_create_electrode_material(env, electrode.material) if electrode.material is not None else None

    return insert_physio_electrode(
        env,
        loris_file_path,
        electrode.name,
        electrode.x,
        electrode.y,
        electrode.z,
        electrode_type,
        material,
        electrode.impedance,
        flush,
    )
