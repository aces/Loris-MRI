from collections.abc import Callable
from typing import TypeVar

from loris_bids_reader.info import BidsAcquisitionInfo

from lib.env import Env
from lib.import_bids_dataset.env import BidsImportEnv
from lib.logging import log, log_error

T = TypeVar('T')


def import_bids_acquisitions(
    env: Env,
    import_env: BidsImportEnv,
    acquisitions: list[tuple[T, BidsAcquisitionInfo]],
    importer: Callable[[T, BidsAcquisitionInfo], None]
):
    """
    Run an import function on a list of BIDS acquisitions, logging the overall import progress,
    and catching the eventual exceptions raised during each import.
    """

    for acquisition, bids_info in acquisitions:
        log(
            env,
            f"Importing {bids_info.data_type} acquisition '{bids_info.name}'...",
        )

        try:
            importer(acquisition, bids_info)
            log(env, f"Successfully imported acquisition '{bids_info.name}'.")
            import_env.imported_acquisitions_count += 1
        except Exception as exception:
            log_error(
                env,
                (
                    f"Error while importing acquisition '{bids_info.name}'. Error message:\n"
                    f"{exception}\n"
                    "Skipping."
                )
            )
            import_env.failed_acquisitions_count += 1
