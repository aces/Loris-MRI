class DetermineSubjectException(Exception):
    """
    Exception raised if some subject IDs cannot be determined using the config file.
    """
    message: str

    def __init__(self, message: str):
        super().__init__(message)
        self.message = message
