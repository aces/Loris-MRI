from pathlib import Path

from lib.db.base import Base
from lib.db.decorators.string_path import StringPath
from lib.db.models.physio_file import DbPhysioFile
from sqlalchemy import ForeignKey
from sqlalchemy.dialects.mysql import INTEGER, VARCHAR
from sqlalchemy.orm import Mapped, mapped_column, relationship


class DbMeegqcFile(Base):
    """
    A MEEGqc file.
    """

    __tablename__ = 'meegqc_file'

    id: Mapped[int] = mapped_column('ID', INTEGER(unsigned=True), primary_key=True, autoincrement=True)
    """
    ID of the MEEGqc file.
    """

    acquisition_file_id: Mapped[int] = mapped_column('AcquisitionFileID', INTEGER(unsigned=True), ForeignKey('physiological_file.PhysiologicalFileID'))
    """
    ID of the acquisition file associated with the MEEGqc file.
    """

    path: Mapped[Path] = mapped_column('Path', StringPath, unique=True)
    """
    Path of the MEEGqc file relative to the LORIS data directory.
    """

    blake2b_hash: Mapped[str] = mapped_column('Blake2bHash', VARCHAR(255))
    """
    Blake2B hash of the MEEGqc file, which may be used to check that the on-disk file data matches
    the file registered in the LORIS database.
    """

    category: Mapped[str] = mapped_column('Kind', VARCHAR(255))
    """
    Category of the MEEGqc file, which may be 'calculation', 'reports', or 'summary_reports'.
    """

    acquisition_file: Mapped['DbPhysioFile'] = relationship('DbPhysioFile')
    """
    Acquisition file associated with the MEEGqc file.
    """
