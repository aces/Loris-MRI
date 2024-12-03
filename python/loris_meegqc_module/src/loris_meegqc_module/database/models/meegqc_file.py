from lib.db.base import Base
from lib.db.models.bids_file import DbBidsFile
from lib.db.models.physio_file import DbPhysioFile
from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship


class DbMeegqcFile(Base):
    """
    A MEEGqc file.
    """

    __tablename__ = 'meegqc_file'

    id: Mapped[int] = mapped_column('ID', primary_key=True, autoincrement=True)
    """
    ID of the MEEGqc file.
    """

    bids_info_id: Mapped[int] = mapped_column('BidsFileID', ForeignKey('bids_file.ID', ondelete='CASCADE'), unique=True)
    """
    ID of the BIDS file entry containing the general file metadata.
    """

    category: Mapped[str] = mapped_column('Category')
    """
    Name of the first directory containing the file relative to the MEEGqc root, or `root` for a
    root-level file.
    """

    bids_info: Mapped['DbBidsFile'] = relationship('DbBidsFile')
    """
    The BIDS file containing entry the general file metadata.
    """

    acquisition_files: Mapped[list['DbPhysioFile']] = relationship('DbPhysioFile', secondary='meegqc_file_acquisition')
    """
    The acquisition files to which the MEEGqc file applies.
    """


class DbMeegqcFileAcquisition(Base):
    """
    An association between an MEEGqc file and an acquisition file to which it applies.
    """

    __tablename__ = 'meegqc_file_acquisition'

    meegqc_file_id: Mapped[int] = mapped_column(
        'MeegqcFileID',
        ForeignKey('meegqc_file.ID', ondelete='CASCADE'),
        primary_key=True,
    )

    acquisition_file_id: Mapped[int] = mapped_column(
        'AcquisitionFileID',
        ForeignKey('physiological_file.PhysiologicalFileID', ondelete='CASCADE'),
        primary_key=True,
    )
