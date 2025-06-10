import os
import shutil
from typing import Any, cast

from lib.db.models.mri_scan_type import DbMriScanType
from lib.db.models.session import DbSession
from lib.db.queries.file import try_get_file_with_hash, try_get_file_with_rel_path
from lib.db.queries.mri_scan_type import try_get_mri_scan_type_with_name
from lib.env import Env
from lib.imaging_lib.bids.dataset import BidsNifti
from lib.imaging_lib.bids.json import add_bids_json_file_parameters
from lib.imaging_lib.bids.tsv_scans import add_scan_tsv_file_parameters
from lib.imaging_lib.bids.util import determine_bids_file_type
from lib.imaging_lib.file import register_imaging_file
from lib.imaging_lib.file_parameter import register_file_parameter, register_file_parameters
from lib.imaging_lib.mri_scan_type import create_mri_scan_type
from lib.imaging_lib.nifti import add_nifti_file_parameters
from lib.imaging_lib.nifti_pic import create_imaging_pic
from lib.import_bids_dataset.env import BidsImportEnv
from lib.logging import log, log_warning
from lib.util.crypto import compute_file_blake2b_hash
from lib.util.fs import get_file_extension

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


def import_bids_nifti(env: Env, import_env: BidsImportEnv, session: DbSession, nifti: BidsNifti):
    """
    Import a BIDS NIfTI file and its associated files in LORIS.
    """

    log(
        env,
        (
            f"Importing MRI file '{nifti.name}'... ({import_env.processed_files_count + 1}"
            f" / {import_env.total_files_count})"
        ),
    )

    # Get the relevant `scans.tsv` row if there is one.

    tsv_scan = nifti.session.get_tsv_scan(nifti.name)
    if tsv_scan is None:
        log_warning(env, f"No scans.tsv row found for file '{nifti.name}', scans.tsv data will be ignored.")

    # Get the path at which to copy the file.

    loris_file_dir_path = os.path.join(
        cast(str, import_env.loris_bids_path),
        f'sub-{session.candidate.psc_id}',
        f'ses-{session.visit_label}',
        nifti.data_type.name,
    )

    loris_file_path = os.path.join(loris_file_dir_path, nifti.name)

    loris_file_rel_path = os.path.relpath(loris_file_path, import_env.data_dir_path)

    # Check whether the file is already registered in LORIS.

    loris_file = try_get_file_with_rel_path(env.db, loris_file_rel_path)
    if loris_file is not None:
        import_env.ignored_files_count += 1
        log(env, f"File '{loris_file_rel_path}' is already registered in LORIS. Skipping.")
        return

    # Get information about the file.

    file_type = get_check_nifti_imaging_file_type(env, nifti)
    file_hash = get_check_nifti_file_hash(env, nifti)
    mri_scan_type = get_nifti_mri_scan_type(env, import_env, nifti)

    # Get the auxiliary files.

    aux_file_paths: list[str] = []

    json_path = nifti.get_json_path()

    bval_path = nifti.get_bval_path()
    if bval_path is not None:
        aux_file_paths.append(bval_path)

    bvec_path = nifti.get_bvec_path()
    if bvec_path is not None:
        aux_file_paths.append(bvec_path)

    # Get the file parameters.

    file_parameters: dict[str, Any] = {}

    if json_path is not None:
        json_loris_path = os.path.join(loris_file_dir_path, os.path.basename(json_path))
        json_loris_rel_path = os.path.relpath(json_loris_path, import_env.data_dir_path)
        add_bids_json_file_parameters(env, json_path, json_loris_rel_path, file_parameters)

    add_nifti_file_parameters(nifti.path, file_hash, file_parameters)

    if nifti.session.tsv_scans_path is not None and tsv_scan is not None:
        add_scan_tsv_file_parameters(tsv_scan, nifti.session.tsv_scans_path, file_parameters)

    for aux_file_path in aux_file_paths:
        aux_file_type = get_file_extension(aux_file_path)
        aux_file_hash = compute_file_blake2b_hash(aux_file_path)
        aux_file_loris_path = os.path.join(loris_file_dir_path, os.path.basename(aux_file_path))
        aux_file_loris_rel_path = os.path.relpath(aux_file_loris_path, import_env.data_dir_path)
        file_parameters[f'bids_{aux_file_type}']              = aux_file_loris_rel_path
        file_parameters[f'bids_{aux_file_type}_blake2b_hash'] = aux_file_hash

    # Copy the files on the file system.

    copy_bids_file(loris_file_dir_path, nifti.path)

    if json_path is not None:
        copy_bids_file(loris_file_dir_path, json_path)

    for aux_file_path in aux_file_paths:
        copy_bids_file(loris_file_dir_path, aux_file_path)

    # Register the file and its parameters in the database.

    echo_time                = file_parameters.get('EchoTime')
    echo_number              = file_parameters.get('EchoNumber')
    phase_encoding_direction = file_parameters.get('PhaseEncodingDirection')

    file = register_imaging_file(
        env,
        file_type,
        loris_file_rel_path,
        session,
        mri_scan_type,
        echo_time,
        echo_number,
        phase_encoding_direction,
    )

    register_file_parameters(env, file, file_parameters)

    # Create and register the file picture.

    pic_rel_path = create_imaging_pic(env, file, True if 'time' in file_parameters else False)

    register_file_parameter(env, file, 'check_pic_filename', pic_rel_path)

    import_env.imported_files_count += 1


def get_check_nifti_imaging_file_type(env: Env, nifti: BidsNifti) -> str:
    """
    Get the BIDS file type of a NIfTI file and raise an exception if that file type is not
    registered in the database.
    """

    file_type = determine_bids_file_type(env, nifti.name)
    if file_type is None:
        raise Exception("No matching file type found in the database.")

    return file_type


def get_check_nifti_file_hash(env: Env, nifti: BidsNifti) -> str:
    """
    Compute the BLAKE2b hash of a NIfTI file and raise an exception if that hash is already
    registered in the database.
    """

    file_hash = compute_file_blake2b_hash(nifti.path)

    file = try_get_file_with_hash(env.db, file_hash)
    if file is not None:
        raise Exception(f"File with hash '{file_hash}' already present in the database.")

    return file_hash


def get_nifti_mri_scan_type(env: Env, import_env: BidsImportEnv, nifti: BidsNifti) -> DbMriScanType | None:
    """
    Get the MRI scan type corresponding to a NIfTI file using its BIDS suffix. Create the MRI scan
    type in the database the suffix is a standard BIDS suffix and the scan type does not already
    exist in the database, or raise an exception if no known scan type is found.
    """

    if nifti.suffix is None:
        raise Exception("No BIDS suffix found in the NIfTI file name, cannot infer the file data type.")

    mri_scan_type = try_get_mri_scan_type_with_name(env.db, nifti.suffix)
    if mri_scan_type is not None:
        return mri_scan_type

    if nifti.suffix not in KNOWN_SUFFIXES_PER_MRI_DATA_TYPE[nifti.data_type.name]:
        if nifti.suffix not in import_env.unknown_scan_types:
            import_env.unknown_scan_types.append(nifti.suffix)

        raise Exception(f"Found unknown MRI file suffix '{nifti.suffix}'.")

    return create_mri_scan_type(env, nifti.suffix)


def copy_bids_file(loris_file_dir_path: str, file_path: str):
    """
    Copy a BIDS file to a directory.
    """

    file_name = os.path.basename(file_path)
    loris_file_path = os.path.join(loris_file_dir_path, file_name)

    if os.path.exists(loris_file_path):
        raise Exception(f"File '{loris_file_path}' already exists in LORIS.")

    os.makedirs(loris_file_dir_path, exist_ok=True)
    shutil.copyfile(file_path, loris_file_path)
