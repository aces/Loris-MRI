from decimal import Decimal

from sqlalchemy import ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship

import lib.db.models.mri_protocol_group as db_mri_protocol_group
import lib.db.models.mri_scan_type as db_mri_scan_type
import lib.db.models.mri_scanner as db_mri_scanner
import lib.db.models.site as db_site
from lib.db.base import Base


class DbMriProtocol(Base):
    __tablename__ = 'mri_protocol'

    id                       : Mapped[int]            = mapped_column('ID', primary_key=True)
    site_id                  : Mapped[int | None]     = mapped_column('CenterID', ForeignKey('psc.CenterID'))
    scanner_id               : Mapped[int | None]     = mapped_column('ScannerID', ForeignKey('mri_scanner.ID'))
    scan_type_id             : Mapped[int]            = mapped_column('MriScanTypeID', ForeignKey('mri_scan_type.MriScanTypeID'))
    tr_min                   : Mapped[Decimal | None] = mapped_column('TR_min')
    tr_max                   : Mapped[Decimal | None] = mapped_column('TR_max')
    te_min                   : Mapped[Decimal | None] = mapped_column('TE_min')
    te_max                   : Mapped[Decimal | None] = mapped_column('TE_max')
    ti_min                   : Mapped[Decimal | None] = mapped_column('TI_min')
    ti_max                   : Mapped[Decimal | None] = mapped_column('TI_max')
    slice_thickness_min      : Mapped[Decimal | None] = mapped_column('slice_thickness_min')
    slice_thickness_max      : Mapped[Decimal | None] = mapped_column('slice_thickness_max')
    xspace_min               : Mapped[int | None]     = mapped_column('xspace_min')
    xspace_max               : Mapped[int | None]     = mapped_column('xspace_max')
    yspace_min               : Mapped[int | None]     = mapped_column('yspace_min')
    yspace_max               : Mapped[int | None]     = mapped_column('yspace_max')
    zspace_min               : Mapped[int | None]     = mapped_column('zspace_min')
    zspace_max               : Mapped[int | None]     = mapped_column('zspace_max')
    xstep_min                : Mapped[Decimal | None] = mapped_column('xstep_min')
    xstep_max                : Mapped[Decimal | None] = mapped_column('xstep_max')
    ystep_min                : Mapped[Decimal | None] = mapped_column('ystep_min')
    ystep_max                : Mapped[Decimal | None] = mapped_column('ystep_max')
    zstep_min                : Mapped[Decimal | None] = mapped_column('zstep_min')
    zstep_max                : Mapped[Decimal | None] = mapped_column('zstep_max')
    time_min                 : Mapped[int | None]     = mapped_column('time_min')
    time_max                 : Mapped[int | None]     = mapped_column('time_max')
    image_type               : Mapped[str | None]     = mapped_column('image_type')
    series_description_regex : Mapped[str | None]     = mapped_column('series_description_regex')
    phase_encoding_direction : Mapped[str | None]     = mapped_column('PhaseEncodingDirection')
    echo_number              : Mapped[str | None]     = mapped_column('EchoNumber')
    protocol_group_id        : Mapped[int]            = mapped_column('MriProtocolGroupID', ForeignKey('mri_protocol_group.MriProtocolGroupID'))

    site           : Mapped['db_site.DbSite | None'] \
        = relationship('DbSite')
    scanner        : Mapped['db_mri_scanner.DbMriScanner | None'] \
        = relationship('DbMriScanner')
    scan_type      : Mapped['db_mri_scan_type.DbMriScanType'] \
        = relationship('DbMriScanType')
    protocol_group : Mapped['db_mri_protocol_group.DbMriProtocolGroup'] \
        = relationship('DbMriProtocolGroup')
