from sqlalchemy.orm import Session as Database

from lib.db.queries.physio import get_physio_file_parameters


def get_physio_file_parameters_dict(db: Database, physio_file_id: int) -> dict[str, str | None]:
    """
    Get the parameters of a physiological file as a dictionary mapping from the name of the
    parameters to their values.
    """

    parameters = get_physio_file_parameters(db, physio_file_id)
    return {
        type.name: parameter.value for type, parameter in parameters
    }
