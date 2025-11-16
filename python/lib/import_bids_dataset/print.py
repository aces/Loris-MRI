from lib.env import Env
from lib.import_bids_dataset.env import BIDSImportEnv
from lib.logging import log


def print_bids_import_summary(env: Env, import_env: BIDSImportEnv):
    """
    Print a summary of this BIDS import process.
    """

    log(
        env,
        (
            f"Processed {import_env.processed_files_count} MRI files, including {import_env.imported_files_count}"
            f" imported files, {import_env.ignored_files_count} ignored files, and {import_env.failed_files_count}"
            " errors."
        ),
    )

    if import_env.unknown_scan_types != []:
        import_env.unknown_scan_types.sort()

        unknwon_scan_types_string = ""
        for unknown_scan_type in import_env.unknown_scan_types:
            unknwon_scan_types_string += f"\n- {unknown_scan_type}"

        log(
            env,
            f"Found {len(import_env.unknown_scan_types)} unknown MRI scan types:{unknwon_scan_types_string}"
        )
