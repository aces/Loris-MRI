from sqlalchemy.orm import DeclarativeBase


a: int = "Hello"


class Base(DeclarativeBase):
    """
    Base SQLAlchemy class that must be inherited by all the ORM model classes.
    """

    pass
