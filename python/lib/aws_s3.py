"""This class interacts with S3 Buckets"""

import boto3
import os

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
        """
        Upload a file to an S3 bucket

        :param file_name: Full path to the file to upload
         :type file_name: str
        :param object_name: S3 object name. It should be identical to the LORIS relative path to data_dir
         :type object_name: str
        """

        # Upload the file
        s3_prefix = f"s3://{self.bucket_name}/"
        s3_file_name = object_name[len(s3_prefix):] if object_name.startswith(s3_prefix) else object_name

        try:
            print(f"Uploading {s3_file_name} to {self.aws_endpoint_url}/{self.bucket_name}")
            self.s3_bucket_obj.upload_file(file_name, s3_file_name)
        except ClientError as err:
            raise Exception(f"{file_name} upload failure - {format(err)}")

    def upload_dir(self, dir_name, object_name):
        """
        Upload a directory to an S3 bucket

        :param dir_name: Full path to the dir to upload
         :type dir_name: str
        :param object_name: S3 object name. It should be identical to the LORIS relative path to data_dir
         :type object_name: str
        """

        for (root, dirs, files) in os.walk(dir_name):
            for file in files:
                self.upload_file(
                    os.path.join(root, file),
                    os.path.join(object_name, root.replace(dir_name, ""), file)
                )

    def check_if_file_key_exists_in_bucket(self, file_key):
        """
        Checks whether a file (key) exists in the bucket. Return True if file found, False otherwise.

        :param file_key: file (or key) to look for in the bucket
         :type file_key: str

        :return: True if file (key) found, False otherwise
         :rtype: bool
        """

        try:
            self.s3_bucket_obj.Object(file_key).get()
        except ClientError as err:
            return False

        return True

    def download_file(self, s3_object_name, destination_file):
        """
        Download a file from an S3 bucket

        :param s3_object_name: S3 object name to download from
         :type s3_object_name: str
        :param destination_file: Full path where the file should be downloaded
         :type destination_file: str
        """

        s3_prefix = f"s3://{self.bucket_name}/"
        s3_file_name = s3_object_name[len(s3_prefix):] if s3_object_name.startswith(s3_prefix) else s3_object_name

        try:
            print(f"Downloading {s3_file_name} from {self.aws_endpoint_url}/{self.bucket_name} to {destination_file}")
            self.s3_bucket_obj.download_file(s3_file_name, destination_file)
        except ClientError as err:
            raise Exception(f"{s3_object_name} download failure = {format(err)}")

    def delete_file(self, s3_object_name):
        """
        Function to delete a s3 file or directory.

        :param s3_object_name: name of the s3 file or directory
         :type s3_object_name: str
        """

        s3_bucket_prefix = f"s3://{self.bucket_name}/"
        s3_file_name = s3_object_name[len(s3_bucket_prefix):] \
            if s3_object_name.startswith(s3_bucket_prefix) else s3_object_name
        objects_to_delete = [{'Key': obj.key} for obj in
                             self.s3_bucket_obj.objects.filter(Prefix=s3_file_name)]
        self.s3_bucket_obj.delete_objects(
            Delete={
                'Objects': objects_to_delete
            }
        )
