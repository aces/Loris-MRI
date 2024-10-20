from sqlalchemy.orm import DeclarativeBase, MappedAsDataclass


class Base(DeclarativeBase, MappedAsDataclass):
    """
    Base SQLAlchemy class that must be inherited by all the ORM model classes.
    """

    pass
