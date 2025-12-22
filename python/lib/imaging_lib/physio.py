from sqlalchemy.orm import Session as Database

from lib.db.queries.physio_parameter import get_physio_file_parameters


def get_physio_file_parameters_dict(db: Database, physio_file_id: int) -> dict[str, str | None]:
    """
    Get the parameters of a physiological file as a dictionary mapping from the name of the
    parameters to their values.
    """

    parameters = get_physio_file_parameters(db, physio_file_id)
    return {
        parameter_type.name: parameter.value for parameter_type, parameter in parameters
    }
