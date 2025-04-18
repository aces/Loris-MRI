#!/usr/bin/env python

import re

from sqlalchemy.orm import Session as Database

from lib.config_file import DatabaseConfig, SessionCandidateConfig, SessionPhantomConfig

mysql: DatabaseConfig = DatabaseConfig(
    host     = 'DBHOST',
    username = 'DBUSER',
    password = 'DBPASS',
    database = 'DBNAME',
    port     = 3306,
)

# Uncomment this statement if your project uses AWS S3.
# s3: S3Config = S3Config(
#     aws_access_key_id     = 'AWS_ACCESS_KEY_ID',
#     aws_secret_access_key = 'AWS_SECRET_ACCESS_KEY',
#     aws_s3_endpoint_url   = 'AWS_S3_ENDPOINT',
#     aws_s3_bucket_name    = 'AWS_S3_BUCKET_NAME',
# )


def get_session_config(db: Database, patient_id: str) -> SessionCandidateConfig | SessionPhantomConfig | None:
    """
    Get the LORIS session configuration for a given patient ID.
    """

    phantom_match   = re.search(r'(pha)|(test)',          patient_id, re.IGNORECASE)
    candidate_match = re.search(r'([^_]+)_(\d+)_([^_]+)', patient_id, re.IGNORECASE)

    if phantom_match:
        return SessionPhantomConfig(
            name    = patient_id,
            site    = 'SITE',  # Change to the relevant site alias.
            project = 'PROJECT',  # Change to the relevant project alias.
        )
    elif candidate_match:
        return SessionCandidateConfig(
            psc_id         = candidate_match.group(1),
            cand_id        = int(candidate_match.group(2)),
            visit_label    = candidate_match.group(3),
            create_session = None,
        )

    return None
