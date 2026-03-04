from pathlib import Path
from typing import Any

from loris_bids_reader.info import BidsAcquisitionInfo
from loris_bids_reader.mri.acquisition import MriAcquisition
from loris_bids_reader.mri.reader import BidsMriDataTypeReader
from loris_utils.crypto import compute_file_blake2b_hash
from loris_utils.error import group_errors_tuple

from lib.db.models.mri_scan_type import DbMriScanType
from lib.db.models.session import DbSession
from lib.db.queries.file import try_get_file_with_hash, try_get_file_with_path
from lib.db.queries.mri_scan_type import try_get_mri_scan_type_with_name
from lib.env import Env
from lib.imaging_lib.file import register_mri_file
from lib.imaging_lib.file_parameter import register_mri_file_parameter, register_mri_file_parameters
from lib.imaging_lib.nifti import add_nifti_spatial_file_parameters
from lib.imaging_lib.nifti_pic import create_nifti_preview_picture
from lib.imaging_lib.scan_type import create_mri_scan_type
from lib.import_bids_dataset.acquisitions import import_bids_acquisitions
from lib.import_bids_dataset.copy_files import copy_loris_bids_file, get_loris_bids_file_path
from lib.import_bids_dataset.env import BidsImportEnv
from lib.import_bids_dataset.file_type import get_check_bids_imaging_file_type_from_extension
from lib.import_bids_dataset.mri_sidecar import add_bids_mri_sidecar_file_parameters
from lib.import_bids_dataset.scans import add_bids_scans_file_parameters
from lib.logging import log

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


def import_bids_mri_data_type(
    env: Env,
    import_env: BidsImportEnv,
    session: DbSession,
    data_type: BidsMriDataTypeReader,
):
    """
    Import the MRI acquisitions found in a BIDS MRI data type directory.
    """

    import_bids_acquisitions(
        env,
        import_env,
        data_type.acquisitions,
        lambda acquisition, bids_info: import_bids_mri_acquisition(
            env,
            import_env,
            session,
            acquisition,
            bids_info,
        ),
    )


def import_bids_mri_acquisition(
    env: Env,
    import_env: BidsImportEnv,
    session: DbSession,
    acquisition: MriAcquisition,
    bids_info: BidsAcquisitionInfo,
):
    """
    Import a BIDS NIfTI file and its associated files in LORIS.
    """

    # The files to copy to LORIS, with the source path on the left and the LORIS path on the right.
    files_to_copy: list[tuple[Path, Path]] = []

    loris_file_path = get_loris_bids_file_path(import_env, session, bids_info.data_type, acquisition.nifti_path)
    files_to_copy.append((acquisition.nifti_path, loris_file_path))

    # Check whether the file is already registered in LORIS.

    loris_file = try_get_file_with_path(env.db, loris_file_path)
    if loris_file is not None:
        import_env.ignored_acquisitions_count += 1
        log(env, f"File '{loris_file_path}' is already registered in LORIS. Skipping.")
        return

    # Get information about the file.

    file_type, file_hash, scan_type = group_errors_tuple(
        f"Error while checking database information for MRI acquisition '{bids_info.name}'.",
        lambda: get_check_bids_imaging_file_type_from_extension(env, acquisition.nifti_path),
        lambda: get_check_bids_nifti_file_hash(env, acquisition),
        lambda: get_check_bids_nifti_mri_scan_type(env, bids_info),
    )

    # Get the auxiliary files.

    # The auxiliary files to the NIfTI file and its sidecar, with the file type on the left and the
    # file path on the right.
    aux_file_paths: list[tuple[str, Path]] = []

    if acquisition.bval_path is not None:
        aux_file_paths.append(('bval', acquisition.bval_path))

    if acquisition.bvec_path is not None:
        aux_file_paths.append(('bvec', acquisition.bvec_path))

    if acquisition.physio_path is not None:
        aux_file_paths.append(('physio', acquisition.physio_path))

    if acquisition.events_path is not None:
        aux_file_paths.append(('events', acquisition.events_path))

    # Get the file parameters.

    file_parameters: dict[str, Any] = {}

    if acquisition.sidecar_file is not None:
        add_bids_mri_sidecar_file_parameters(env, acquisition.sidecar_file, file_parameters)
        json_loris_path = get_loris_bids_file_path(
            import_env,
            session,
            bids_info.data_type,
            acquisition.sidecar_file.path,
        )

        files_to_copy.append((acquisition.sidecar_file.path, json_loris_path))
        file_parameters['bids_json_file']              = json_loris_path
        file_parameters['bids_json_file_blake2b_hash'] = compute_file_blake2b_hash(acquisition.sidecar_file.path)

    add_nifti_spatial_file_parameters(acquisition.nifti_path, file_parameters)
    file_parameters['file_blake2b_hash'] = file_hash

    if bids_info.scans_file is not None and bids_info.scan_row is not None:
        add_bids_scans_file_parameters(bids_info.scans_file, bids_info.scan_row, file_parameters)

    for aux_file_type, aux_file_path in aux_file_paths:
        aux_file_hash = compute_file_blake2b_hash(aux_file_path)
        aux_file_loris_path = get_loris_bids_file_path(import_env, session, bids_info.data_type, aux_file_path)
        files_to_copy.append((aux_file_path, aux_file_loris_path))
        file_parameters[f'bids_{aux_file_type}']              = str(aux_file_loris_path)
        file_parameters[f'bids_{aux_file_type}_blake2b_hash'] = aux_file_hash

    # Copy the files on the file system.
    for copied_file_path, loris_copied_file_path in files_to_copy:
        copy_loris_bids_file(import_env, copied_file_path, loris_copied_file_path)

    # Register the file and its parameters in the database.

    file = register_mri_file(
        env,
        loris_file_path,
        file_type,
        session,
        scan_type,
        None,
        None,
        file_parameters.get('SeriesInstanceUID'),
        file_parameters.get('EchoTime'),
        file_parameters.get('EchoNumber'),
        file_parameters.get('PhaseEncodingDirection'),
        bids_info.scan_row.get_acquisition_time() if bids_info.scan_row is not None else None,
        False,
    )

    register_mri_file_parameters(env, file, file_parameters)

    env.db.commit()

    # Create and register the file picture.

    pic_rel_path = create_nifti_preview_picture(env, file)

    register_mri_file_parameter(env, file, 'check_pic_filename', str(pic_rel_path))

    env.db.commit()


def get_check_bids_nifti_file_hash(env: Env, acquisition: MriAcquisition) -> str:
    """
    Compute the BLAKE2b hash of a NIfTI file and raise an exception if that hash is already
    registered in the database.
    """

    file_hash = compute_file_blake2b_hash(acquisition.nifti_path)

    file = try_get_file_with_hash(env.db, file_hash)
    if file is not None:
        raise Exception(f"File with hash '{file_hash}' already present in the database.")

    return file_hash


def get_check_bids_nifti_mri_scan_type(env: Env, bids_info: BidsAcquisitionInfo) -> DbMriScanType:
    """
    Get the MRI scan type corresponding to a BIDS MRI acquisition using its BIDS suffix. Create the
    MRI scan type in the database the suffix is a standard BIDS suffix and the scan type does not
    already exist in the database, or raise an exception if no known scan type is found.
    """

    if bids_info.suffix is None:
        raise Exception("No BIDS suffix found in the NIfTI file name, cannot infer the file data type.")

    mri_scan_type = try_get_mri_scan_type_with_name(env.db, bids_info.suffix)
    if mri_scan_type is not None:
        return mri_scan_type

    if bids_info.suffix not in KNOWN_SUFFIXES_PER_MRI_DATA_TYPE[bids_info.data_type]:
        raise Exception(f"Found unknown MRI file suffix '{bids_info.suffix}'.")

    return create_mri_scan_type(env, bids_info.suffix)
