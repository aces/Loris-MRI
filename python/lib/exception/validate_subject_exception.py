class ValidateSubjectException(Exception):
    """
    Exception raised if some subject IDs validation fails.
    """

    message: str

    def __init__(self, message: str):
        super().__init__(message)
        self.message = message
