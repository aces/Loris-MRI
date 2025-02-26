"""
A bunch of functions to convert values between (possibly empty) strings and
different types of values.
"""

import hashlib
import os
from datetime import date, datetime


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


def make_hash(path: str, with_name: bool = False):
    """
    Get the MD5 sum hash of a file, with or without the filename appended.
    """

    with open(path, 'rb') as file:
        hash = hashlib.md5(file.read()).hexdigest()

    if with_name:
        hash = f'{hash}   {os.path.basename(path)}'

    return hash
