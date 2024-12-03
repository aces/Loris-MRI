from lib.env import Env
from lib.import_bids_dataset.env import BidsImportEnv
from lib.logging import log


def print_bids_import_summary(env: Env, import_env: BidsImportEnv):
    """
    Print a summary of this BIDS import process.
    """

    log(
        env,
        (
            f"Processed {import_env.processed_files_count} acquisitions, including {import_env.imported_files_count}"
            f" imports, {import_env.ignored_files_count} ignores, and {import_env.failed_files_count}"
            " errors."
        ),
    )

    if import_env.unknown_mri_scan_types != []:
        import_env.unknown_mri_scan_types.sort()

        unknwon_scan_types_string = ""
        for unknown_status_type in import_env.unknown_mri_scan_types:
            unknwon_scan_types_string += f"\n- {unknown_status_type}"

        log(
            env,
            f"Found {len(import_env.unknown_mri_scan_types)} unknown MRI scan types:{unknwon_scan_types_string}"
        )

    if import_env.unknown_physio_channel_types != []:
        import_env.unknown_physio_channel_types.sort()

        unknown_channel_types_string = ""
        for unknown_channel_type in import_env.unknown_physio_channel_types:
            unknown_channel_types_string += f"\n- {unknown_channel_type}"

        log(
            env,
            (
                f"Found {len(import_env.unknown_physio_channel_types)} unknown physiological channel types:"
                f"{unknown_channel_types_string}"
            ),
        )

    if import_env.unknown_physio_status_types != []:
        import_env.unknown_physio_status_types.sort()

        unknown_status_types_string = ""
        for unknown_status_type in import_env.unknown_physio_status_types:
            unknown_status_types_string += f"\n- {unknown_status_type}"

        log(
            env,
            (
                f"Found {len(import_env.unknown_physio_status_types)} unknown physiological status types:"
                f"{unknown_status_types_string}"
            ),
        )
