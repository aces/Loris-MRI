"""This class interacts with S3 Buckets"""

import boto3

from botocore.exceptions import ClientError


__license__ = "GPLv3"


class AwsS3:

    def __init__(self, aws_access_key_id, aws_secret_access_key, aws_endpoint_url, bucket_name):

        self.aws_access_key_id = aws_access_key_id
        self.aws_secret_access_key = aws_secret_access_key
        self.aws_endpoint_url = aws_endpoint_url
        self.bucket_name = bucket_name

        self.s3 = self.connect_to_s3_bucket()
        self.s3_bucket_obj = self.s3.Bucket(self.bucket_name)

    def connect_to_s3_bucket(self):
        """

        """

        # connect to S3 resource (to have access to
        try:
            session = boto3.session.Session()
            s3 = session.resource(
                service_name="s3",
                aws_access_key_id=self.aws_access_key_id,
                aws_secret_access_key=self.aws_secret_access_key,
                endpoint_url=self.aws_endpoint_url
            )
        except ClientError as err:
            raise Exception("S3 connection failure: " + format(err))

        if s3.Bucket(self.bucket_name) not in s3.buckets.all():
            raise Exception(f"S3 <{self.bucket_name}> bucket not found in <{self.aws_endpoint_url}>")

        return s3

    def upload_file(self, file_name, object_name):
        """Upload a file to an S3 bucket

        :param file_name: Full path to the file to upload
         :type file_name: str
        :param object_name: S3 object name. It should be identical to the LORIS relative path to data_dir
         :type object_name: str
        """

        # Upload the file
        try:
            print(f"Uploading {object_name} to {self.aws_endpoint_url}/{self.bucket_name}")
            self.s3_bucket_obj.upload_file(file_name, object_name)
        except ClientError as err:
            raise Exception(f"{file_name} upload failure - {format(err)}")
