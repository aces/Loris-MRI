#!/usr/bin/env python

import re
from lib.imaging import Imaging

mysql = {
    'host'    : 'DBHOST',
    'username': 'DBUSER',
    'passwd'  : 'DBPASS',
    'database': 'DBNAME',
    'port'    : ''
}

s3 = {
    'aws_access_key_id'    : 'AWS_ACCESS_KEY_ID',
    'aws_secret_access_key': 'AWS_SECRET_ACCESS_KEY',
    'aws_s3_endpoint_url'  : 'AWS_S3_ENDPOINT',
    'aws_s3_bucket_name'   : 'AWS_S3_BUCKET_NAME',
}


def get_subject_ids(db, dicom_value=None, scanner_id=None):

    subject_id_dict = {}

    imaging = Imaging(db, False)

    phantom_match   = re.search('(pha)|(test)', dicom_value, re.IGNORECASE)
    candidate_match = re.search('([^_]+)_(\d+)_([^_]+)', dicom_value, re.IGNORECASE)

    if phantom_match:
        subject_id_dict['isPhantom']  = True
        subject_id_dict['CandID']     = imaging.get_scanner_candid(scanner_id)
        subject_id_dict['visitLabel'] = dicom_value.strip()
        subject_id_dict['createVisitLabel'] = 1
    elif candidate_match:
        subject_id_dict['isPhantom']  = False
        subject_id_dict['PSCID']      = candidate_match.group(1)
        subject_id_dict['CandID']     = candidate_match.group(2)
        subject_id_dict['visitLabel'] = candidate_match.group(3)
        subject_id_dict['createVisitLabel'] = 0

    return subject_id_dict
