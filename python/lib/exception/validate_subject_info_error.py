class ValidateSubjectInfoError(Exception):
    """
    Exception raised if some subject information validation fails.
    """

    message: str

    def __init__(self, message: str):
        super().__init__(message)
        self.message = message
