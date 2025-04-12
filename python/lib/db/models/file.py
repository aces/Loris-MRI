from datetime import date

from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.models.parameter_file as db_parameter_file
import lib.db.models.session as db_session
from lib.db.base import Base


class DbFile(Base):
    __tablename__ = 'files'

    id                             : Mapped[int]          = mapped_column('FileID', primary_key=True)
    session_id                     : Mapped[int]          = mapped_column('SessionID', ForeignKey('session.ID'))
    file_name                      : Mapped[str]          = mapped_column('File')
    series_uid                     : Mapped[str | None]   = mapped_column('SeriesUID')
    echo_time                      : Mapped[float | None] = mapped_column('EchoTime')
    phase_encoding_direction       : Mapped[str | None]   = mapped_column('PhaseEncodingDirection')
    echo_number                    : Mapped[str | None]   = mapped_column('EchoNumber')
    coordinate_space               : Mapped[str | None]   = mapped_column('CoordinateSpace')
    output_type                    : Mapped[str]          = mapped_column('OutputType')
    scan_type_id                   : Mapped[int | None]   = mapped_column('MriScanTypeID')
    file_type                      : Mapped[str | None]   = mapped_column('FileType')
    inserted_by_user_id            : Mapped[str]          = mapped_column('InsertedByUserID')
    insert_time                    : Mapped[int]          = mapped_column('InsertTime')
    source_pipeline                : Mapped[str | None]   = mapped_column('SourcePipeline')
    pipeline_date                  : Mapped[date | None]  = mapped_column('PipelineDate')
    source_file_id                 : Mapped[int | None]   = mapped_column('SourceFileID')
    process_protocol_id            : Mapped[int | None]   = mapped_column('ProcessProtocolID')
    caveat                         : Mapped[bool | None]  = mapped_column('Caveat')
    dicom_archive_id               : Mapped[int | None]   = mapped_column('TarchiveSource')
    hrrt_archive_id                : Mapped[int | None]   = mapped_column('HrrtArchiveID')
    scanner_id                     : Mapped[int | None]   = mapped_column('ScannerID')
    acquisition_order_per_modality : Mapped[int | None]   = mapped_column('AcqOrderPerModality')
    acquisition_date               : Mapped[date | None]  = mapped_column('AcquisitionDate')

    session    : Mapped['db_session.DbSession'] \
        = relationship('DbSession', back_populates='files')
    parameters : Mapped[list['db_parameter_file.DbParameterFile']] \
        = relationship('DbParameterFile', back_populates='file')
