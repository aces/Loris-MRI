class DetermineSubjectInfoError(Exception):
    """
    Exception raised if some subject information cannot be determined from the configuration file.
    """

    message: str

    def __init__(self, message: str):
        super().__init__(message)
        self.message = message
