#!/usr/bin/env python

import re
from lib.database import Database
from lib.imaging import Imaging
from lib.dataclass.config import CreateVisitConfig, DatabaseConfig, S3Config, SubjectConfig


mysql: DatabaseConfig = DatabaseConfig(
    host     = 'DBHOST',
    username = 'DBUSER',
    password = 'DBPASS',
    database = 'DBNAME',
    port     = 3306,
)

# This statement can be omitted if the project does not use AWS S3.
s3: S3Config = S3Config(
    aws_access_key_id     = 'AWS_ACCESS_KEY_ID',
    aws_secret_access_key = 'AWS_SECRET_ACCESS_KEY',
    aws_s3_endpoint_url   = 'AWS_S3_ENDPOINT',
    aws_s3_bucket_name    = 'AWS_S3_BUCKET_NAME',
)


def get_subject_ids(db: Database, subject_name: str, scanner_id: int | None = None) -> SubjectConfig | None:
    imaging = Imaging(db, False)

    phantom_match   = re.search(r'(pha)|(test)', subject_name, re.IGNORECASE)
    candidate_match = re.search(r'([^_]+)_(\d+)_([^_]+)', subject_name, re.IGNORECASE)

    if phantom_match:
        return SubjectConfig.from_phantom(
            name         = subject_name,
            cand_id      = imaging.get_scanner_candid(scanner_id),
            visit_label  = subject_name.strip(),
            create_visit = CreateVisitConfig(
               project_id = 1, # Change to relevant project ID
               cohort_id  = 1, # Change to relevant cohort ID
            ),
        )
    elif candidate_match:
        return SubjectConfig.from_candidate(
            name         = subject_name,
            psc_id       = candidate_match.group(1),
            cand_id      = int(candidate_match.group(2)),
            visit_label  = candidate_match.group(3),
            create_visit = None,
        )

    return None
