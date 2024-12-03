from pathlib import Path
from typing import Any

from loris_bids_reader.files.scans import BidsScanTsvRow
from loris_bids_reader.mri.data_type import BidsMriAcquisition

from lib.db.models.mri_scan_type import DbMriScanType
from lib.db.models.session import DbSession
from lib.db.queries.file import try_get_file_with_hash, try_get_file_with_path
from lib.db.queries.mri_scan_type import try_get_mri_scan_type_with_name
from lib.env import Env
from lib.imaging_lib.file import register_mri_file
from lib.imaging_lib.file_parameter import register_mri_file_parameter, register_mri_file_parameters
from lib.imaging_lib.mri_scan_type import create_mri_scan_type
from lib.imaging_lib.nifti import add_nifti_spatial_file_parameters
from lib.imaging_lib.nifti_pic import create_nifti_preview_picture
from lib.import_bids_dataset.copy_files import copy_bids_file, get_loris_file_path
from lib.import_bids_dataset.env import BidsImportEnv
from lib.import_bids_dataset.file_type import get_check_imaging_file_type
from lib.import_bids_dataset.json import add_bids_json_file_parameters
from lib.import_bids_dataset.scans import add_scan_tsv_file_parameters
from lib.logging import log
from lib.util.crypto import compute_file_blake2b_hash
from lib.util.error import group_errors_tuple
from lib.util.path import get_path_extension

KNOWN_SUFFIXES_PER_MRI_DATA_TYPE = {
    'anat': [
        'T1w', 'T2w', 'T1rho', 'T1map', 'T2map', 'T2star', 'FLAIR', 'FLASH', 'PD', 'PDmap', 'PDT2',
        'inplaneT1', 'inplaneT2', 'angio',
    ],
    'func': [
        'bold', 'cbv', 'phase',
    ],
    'dwi': [
        'dwi', 'sbref',
    ],
    'fmap': [
        'phasediff', 'magnitude1', 'magnitude2', 'phase1', 'phase2', 'fieldmap', 'epi',
    ],
}


def import_bids_mri_acquisition(
    env: Env,
    import_env: BidsImportEnv,
    session: DbSession,
    acquisition: BidsMriAcquisition,
    tsv_scan: BidsScanTsvRow | None,
):
    """
    Import a BIDS NIfTI file and its associated files in LORIS.
    """

    loris_file_path = get_loris_file_path(import_env, session, acquisition, acquisition.nifti_path)

    # Check whether the file is already registered in LORIS.

    loris_file = try_get_file_with_path(env.db, loris_file_path)
    if loris_file is not None:
        import_env.ignored_files_count += 1
        log(env, f"File '{loris_file_path}' is already registered in LORIS. Skipping.")
        return

    # Get information about the file.

    file_type, file_hash, scan_type = group_errors_tuple(
        f"Error while checking database information for MRI acquisition '{acquisition.name}'.",
        lambda: get_check_imaging_file_type(env, acquisition.nifti_path.name),
        lambda: get_check_bids_nifti_file_hash(env, acquisition),
        lambda: get_check_bids_nifti_mri_scan_type(env, import_env, acquisition),
    )

    # Get the auxiliary files.

    aux_file_paths: list[Path] = []

    if acquisition.bval_path is not None:
        aux_file_paths.append(acquisition.bval_path)

    if acquisition.bvec_path is not None:
        aux_file_paths.append(acquisition.bvec_path)

    # Get the file parameters.

    file_parameters: dict[str, Any] = {}

    if acquisition.sidecar is not None:
        json_loris_path = get_loris_file_path(import_env, session, acquisition, acquisition.sidecar.path)
        add_bids_json_file_parameters(env, acquisition.sidecar.path, json_loris_path, file_parameters)

    add_nifti_spatial_file_parameters(acquisition.nifti_path, file_parameters)
    file_parameters['file_blake2b_hash'] = file_hash

    if acquisition.session.tsv_scans is not None and tsv_scan is not None:
        add_scan_tsv_file_parameters(tsv_scan, acquisition.session.tsv_scans.path, file_parameters)

    for aux_file_path in aux_file_paths:
        aux_file_type = get_path_extension(aux_file_path)
        aux_file_hash = compute_file_blake2b_hash(aux_file_path)
        aux_file_loris_path = get_loris_file_path(import_env, session, acquisition, aux_file_path)
        file_parameters[f'bids_{aux_file_type}']              = str(aux_file_loris_path)
        file_parameters[f'bids_{aux_file_type}_blake2b_hash'] = aux_file_hash

    # Copy the files on the file system.

    if import_env.loris_bids_path is not None:
        copy_bids_file(import_env.loris_bids_path, session, acquisition, acquisition.nifti_path)

        if acquisition.sidecar is not None:
            copy_bids_file(import_env.loris_bids_path, session, acquisition, acquisition.sidecar.path)

        for aux_file_path in aux_file_paths:
            copy_bids_file(import_env.loris_bids_path, session, acquisition, aux_file_path)

    # Register the file and its parameters in the database.

    echo_time                = file_parameters.get('EchoTime')
    echo_number              = file_parameters.get('EchoNumber')
    phase_encoding_direction = file_parameters.get('PhaseEncodingDirection')

    file = register_mri_file(
        env,
        file_type,
        loris_file_path,
        session,
        scan_type,
        None,
        None,
        None,
        echo_time,
        echo_number,
        phase_encoding_direction,
        None,
        False,
    )

    register_mri_file_parameters(env, file, file_parameters)

    # Create and register the file picture.

    pic_rel_path = create_nifti_preview_picture(env, file)

    register_mri_file_parameter(env, file, 'check_pic_filename', str(pic_rel_path))

    import_env.imported_files_count += 1


def get_check_bids_nifti_file_hash(env: Env, acquisition: BidsMriAcquisition) -> str:
    """
    Compute the BLAKE2b hash of a NIfTI file and raise an exception if that hash is already
    registered in the database.
    """

    file_hash = compute_file_blake2b_hash(acquisition.nifti_path)

    file = try_get_file_with_hash(env.db, file_hash)
    if file is not None:
        raise Exception(f"File with hash '{file_hash}' already present in the database.")

    return file_hash


def get_check_bids_nifti_mri_scan_type(
    env: Env,
    import_env: BidsImportEnv,
    acquisition: BidsMriAcquisition,
) -> DbMriScanType:
    """
    Get the MRI scan type corresponding to a BIDS MRI acquisition using its BIDS suffix. Create the
    MRI scan type in the database the suffix is a standard BIDS suffix and the scan type does not
    already exist in the database, or raise an exception if no known scan type is found.
    """

    if acquisition.suffix is None:
        raise Exception("No BIDS suffix found in the NIfTI file name, cannot infer the file data type.")

    mri_scan_type = try_get_mri_scan_type_with_name(env.db, acquisition.suffix)
    if mri_scan_type is not None:
        return mri_scan_type

    if acquisition.suffix not in KNOWN_SUFFIXES_PER_MRI_DATA_TYPE[acquisition.data_type.name]:
        import_env.register_unknown_mri_scan_type(acquisition.suffix)

        raise Exception(f"Found unknown MRI file suffix '{acquisition.suffix}'.")

    return create_mri_scan_type(env, acquisition.suffix)
