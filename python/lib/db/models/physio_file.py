from datetime import datetime
from pathlib import Path

from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.models.meg_ctf_head_shape_file as db_meg_ctf_head_shape_file
import lib.db.models.physio_channel as db_physio_channel
import lib.db.models.physio_event_archive as db_physio_event_archive
import lib.db.models.physio_event_file as db_physio_event_file
import lib.db.models.physio_file_archive as db_physio_file_archive
import lib.db.models.physio_file_parameter as db_phyiso_file_parameter
import lib.db.models.physio_modality as db_physio_modality
import lib.db.models.physio_output_type as db_physio_output_type
import lib.db.models.session as db_session
from lib.db.base import Base
from lib.db.decorators.string_path import StringPath


class DbPhysioFile(Base):
    __tablename__ = 'physiological_file'

    id               : Mapped[int]             = mapped_column('PhysiologicalFileID', primary_key=True)
    modality_id      : Mapped[int | None]      = mapped_column('PhysiologicalModalityID', ForeignKey('physiological_modality.PhysiologicalModalityID'))
    output_type_id   : Mapped[int]             = mapped_column('PhysiologicalOutputTypeID', ForeignKey('physiological_output_type.PhysiologicalOutputTypeID'))
    session_id       : Mapped[int]             = mapped_column('SessionID', ForeignKey('session.ID'))
    insert_time      : Mapped[datetime]        = mapped_column('InsertTime', default=datetime.now)
    type             : Mapped[str | None]      = mapped_column('FileType')
    acquisition_time : Mapped[datetime | None] = mapped_column('AcquisitionTime')
    inserted_by_user : Mapped[str]             = mapped_column('InsertedByUser')
    index            : Mapped[int | None]      = mapped_column('Index')
    parent_id        : Mapped[int | None]      = mapped_column('ParentID')

    path: Mapped[Path] = mapped_column('FilePath', StringPath)
    """
    The path of this physiological file, which may be a directory (notably for MEG CTF data). The
    path is relative to the LORIS data directory.
    """

    download_path: Mapped[Path] = mapped_column('DownloadPath', StringPath)
    """
    The path from which to download this physiological file, which is guaranteed to be a normal
    file or an archive. The path is relative to the LORIS data directory.
    """

    head_shape_file_id: Mapped[int | None] = mapped_column('HeadShapeFileID', ForeignKey('meg_ctf_head_shape_file.ID'))
    """
    ID of the head shape file associated to this file, which is only present for MEG CTF files.
    """

    output_type   : Mapped['db_physio_output_type.DbPhysioOutputType']             = relationship('DbPhysioOutputType')
    modality      : Mapped['db_physio_modality.DbPhysioModality | None']           = relationship('DbPhysioModality')
    session       : Mapped['db_session.DbSession']                                 = relationship('DbSession')
    archive       : Mapped['db_physio_file_archive.DbPhysioFileArchive | None']    = relationship('DbPhysioFileArchive', back_populates='physio_file')
    event_archive : Mapped['db_physio_event_archive.DbPhysioEventArchive | None']  = relationship('DbPhysioEventArchive', back_populates='physio_file')
    channels      : Mapped[list['db_physio_channel.DbPhysioChannel']]              = relationship('DbPhysioChannel', back_populates='physio_file')
    parameters    : Mapped[list['db_phyiso_file_parameter.DbPhysioFileParameter']] = relationship('DbPhysioFileParameter', back_populates='file')
    event_files   : Mapped[list['db_physio_event_file.DbPhysioEventFile']]         = relationship('DbPhysioEventFile', back_populates='physio_file')

    head_shape_file: Mapped['db_meg_ctf_head_shape_file.DbMegCtfHeadShapeFile | None'] = relationship('DbMegCtfHeadShapeFile')
    """
    The head shape file associated to this file, which is only present for MEG CTF files.
    """
