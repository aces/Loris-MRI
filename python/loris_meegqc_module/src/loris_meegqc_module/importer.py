import re
from collections.abc import Sequence
from enum import Enum
from pathlib import Path

from lib.db.models.physio_file import DbPhysioFile
from lib.db.queries.candidate import try_get_candidate_with_psc_id
from lib.db.queries.physio import get_candidate_ephys_files
from lib.env import Env
from lib.logging import log, log_error
from loris_bids_importer.copy_files import copy_loris_bids_file
from loris_bids_importer.env import BidsImportEnv
from loris_bids_utils.reader import BidsDatasetReader
from loris_utils.crypto import compute_file_blake2b_hash

from loris_meegqc_module.database.models.meegqc_file import DbMeegqcFile
from loris_meegqc_module.database.queries.meegqc_file import try_get_meegqc_file_with_path


class MeegqcFileKind(Enum):
    CALCULATION     = 'calculation'
    REPORTS         = 'reports'
    SUMMARY_REPORTS = 'summary_reports'


def import_meegqc_derivatives(env: Env, import_env: BidsImportEnv, bids_dataset: BidsDatasetReader):
    meegqc_path = bids_dataset.path / 'derivatives' / 'MEG_QC'
    if not meegqc_path.exists():
        log(env, "No MEEGqc derivatives found in the BIDS dataset. Skipping.")
        return

    calculation_path = meegqc_path / 'calculation'

    reports_path = meegqc_path / 'reports'

    summary_reports_path = meegqc_path / 'summary_reports'

    if calculation_path.exists():
        import_meegqc_files(env, import_env, calculation_path, MeegqcFileKind.CALCULATION)

    if reports_path.exists():
        import_meegqc_files(env, import_env, reports_path, MeegqcFileKind.REPORTS)

    if summary_reports_path.exists():
        import_meegqc_files(env, import_env, summary_reports_path, MeegqcFileKind.SUMMARY_REPORTS)


def import_meegqc_files(env: Env, import_env: BidsImportEnv, files_path: Path, kind: MeegqcFileKind):
    for subject_path in files_path.iterdir():
        # TODO: Use a general BIDS file name abstraction.
        subject_match = re.match(r'sub-(.+)', subject_path.name)
        if not subject_match:
            continue

        subject_label = subject_match.group(1)

        for data_type in ['eeg', 'meg']:
            data_type_path = subject_path / data_type
            if not data_type_path.exists():
                continue

            for file_path in data_type_path.glob('**/*'):
                if not file_path.is_file():
                    continue

                try:
                    import_meegqc_file(env, import_env, subject_label, file_path, kind)
                except Exception as exception:
                    log_error(env, f"Error while importing MEEGqc file {file_path}. Error message:\n{exception}")


def import_meegqc_file(
    env: Env,
    import_env: BidsImportEnv,
    subject_label: str,
    meegqc_file_path: Path,
    kind: MeegqcFileKind,
):
    log(env, f"Importing MEEGqc {kind.value} file '{meegqc_file_path}'.")

    # TODO: Make a general function for PSCID and CandID.
    candidate = try_get_candidate_with_psc_id(env.db, subject_label)
    if candidate is None:
        raise Exception(
            f"Could not find candidate with PSCID {subject_label} in the database. Skipping.",
        )

    candidate_acquisition_files = get_candidate_ephys_files(env.db, candidate.id)

    acquisition_file = find_acquisition_file(candidate_acquisition_files, meegqc_file_path)

    blake2b_hash = compute_file_blake2b_hash(meegqc_file_path)

    loris_file_path = (
        meegqc_file_path.relative_to(import_env.data_dir_path)
        if import_env.loris_bids_path is None else
        Path('derivatives') / 'MEG_QC' / f'sub-{candidate.psc_id}' / kind.value / meegqc_file_path
    )

    current_meegqc_file = try_get_meegqc_file_with_path(env.db, loris_file_path)
    if current_meegqc_file is not None:
        log(env, f"A MEEGqc file with path {loris_file_path} already exists in the database. Skipping.")
        return

    copy_loris_bids_file(import_env, meegqc_file_path, loris_file_path)

    env.db.add(DbMeegqcFile(
        acquisition_file_id=acquisition_file.id,
        file_path=loris_file_path,
        kind=kind.value,
        blake2b_hash=blake2b_hash
    ))

    env.db.commit()


def find_acquisition_file(acquisition_files: Sequence[DbPhysioFile], meegqc_file_path: Path) -> DbPhysioFile:
    # TODO: Use a general BIDS file name abstraction.
    meegqc_file_pattern = re.sub(r'desc-[^_]+', '*', meegqc_file_path.stem)
    matching_acquisition_files: list[DbPhysioFile] = []
    for acquisition_file in acquisition_files:
        if re.match(meegqc_file_pattern, acquisition_file.path.stem):
            matching_acquisition_files.append(acquisition_file)

    match matching_acquisition_files:
        case []:
            raise Exception(
                f"Could not find any acquisition file for MEEGqc file {meegqc_file_path}.",
            )
        case [acquisition_file]:
            return acquisition_file
        case _:
            matching_files_string = "\n- ".join(file.path.name for file in matching_acquisition_files)
            raise Exception(
                f"Found multiple acquisition files for MEEGqc file {meegqc_file_path}:{matching_files_string}"
            )
