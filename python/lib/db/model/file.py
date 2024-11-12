from datetime import date
from typing import Optional

from sqlalchemy.orm import Mapped, mapped_column

from lib.db.base import Base


class DbFile(Base):
    __tablename__ = 'files'

    id                             : Mapped[int]             = mapped_column('FileID', primary_key=True)
    session_id                     : Mapped[int]             = mapped_column('SessionID')
    file_name                      : Mapped[str]             = mapped_column('File')
    series_uid                     : Mapped[Optional[str]]   = mapped_column('SeriesUID')
    echo_time                      : Mapped[Optional[float]] = mapped_column('EchoTime')
    phase_encoding_direction       : Mapped[Optional[str]]   = mapped_column('PhaseEncodingDirection')
    echo_number                    : Mapped[Optional[str]]   = mapped_column('EchoNumber')
    coordinate_space               : Mapped[Optional[str]]   = mapped_column('CoordinateSpace')
    output_type                    : Mapped[str]             = mapped_column('OutputType')
    acquisition_protocol_id        : Mapped[Optional[int]]   = mapped_column('AcquisitionProtocolID')
    file_type                      : Mapped[Optional[str]]   = mapped_column('FileType')
    inserted_by_user_id            : Mapped[str]             = mapped_column('InsertedByUserID')
    insert_time                    : Mapped[int]             = mapped_column('InsertTime')
    source_pipeline                : Mapped[Optional[str]]   = mapped_column('SourcePipeline')
    pipeline_date                  : Mapped[Optional[date]]  = mapped_column('PipelineDate')
    source_file_id                 : Mapped[Optional[int]]   = mapped_column('SourceFileID')
    process_protocol_id            : Mapped[Optional[int]]   = mapped_column('ProcessProtocolID')
    caveat                         : Mapped[Optional[bool]]  = mapped_column('Caveat')
    dicom_archive_id               : Mapped[Optional[int]]   = mapped_column('TarchiveSource')
    hrrt_archive_id                : Mapped[Optional[int]]   = mapped_column('HrrtArchiveID')
    scanner_id                     : Mapped[Optional[int]]   = mapped_column('ScannerID')
    acquisition_order_per_modality : Mapped[Optional[int]]   = mapped_column('AcqOrderPerModality')
    acquisition_date               : Mapped[Optional[date]]  = mapped_column('AcquisitionDate')
