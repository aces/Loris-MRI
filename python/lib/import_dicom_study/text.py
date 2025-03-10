"""
A bunch of functions to convert values between (possibly empty) strings and
different types of values.
"""

import os
from datetime import date, datetime

from lib.util.crypto import compute_file_md5_hash


def write_value(value: str | int | float | None):
    if value is None:
        return ''

    return str(value)


def write_datetime(datetime: datetime):
    return datetime.strftime('%Y-%m-%d %H:%M:%S')


def write_date(date: date):
    return date.strftime('%Y-%m-%d')


def write_date_none(date: date | None):
    if date is None:
        return None

    return write_date(date)


def read_none(string: str):
    if string == '':
        return None

    return string


def read_date_none(string: str | None):
    if string is None:
        return None

    return datetime.strptime(string, '%Y-%m-%d').date()


def read_dicom_date_none(string: str | None):
    if string is None:
        return None

    return datetime.strptime(string, '%Y%m%d').date()


def read_int_none(string: str | None):
    if string is None:
        return None

    return int(string)


def read_float_none(string: str | None):
    if string is None:
        return None

    return float(string)


def compute_md5_hash_with_name(path: str):
    """
    Get the MD5 sum hash of a file with the filename appended.
    """

    return f'{compute_file_md5_hash(path)}   {os.path.basename(path)}'
