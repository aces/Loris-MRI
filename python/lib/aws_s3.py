"""This class interacts with S3 Buckets"""

import boto3
import os
from botocore.exceptions import ClientError, EndpointConnectionError

__license__ = "GPLv3"


class AwsS3:

    def __init__(self, aws_access_key_id, aws_secret_access_key, aws_endpoint_url, bucket_name):

        self.aws_access_key_id = aws_access_key_id
        self.aws_secret_access_key = aws_secret_access_key
        self.aws_endpoint_url = aws_endpoint_url
        self.bucket_name = bucket_name
        self.s3 = self.connect_to_s3_bucket()
        if self.s3:
            self.s3_bucket_obj = self.s3.Bucket(self.bucket_name)

    def connect_to_s3_bucket(self):
        """

        """

        # connect to S3 resource
        try:
            session = boto3.session.Session()
            s3 = session.resource(
                service_name="s3",
                aws_access_key_id=self.aws_access_key_id,
                aws_secret_access_key=self.aws_secret_access_key,
                endpoint_url=self.aws_endpoint_url
            )
            if s3.Bucket(self.bucket_name) not in s3.buckets.all():
                print(f"\n[ERROR   ] S3 <{self.bucket_name}> bucket not found in <{self.aws_endpoint_url}>\n")
                return
        except ClientError as err:
            print(f'\n[ERROR   ] S3 connection failure: {format(err)}\n')
            return
        except EndpointConnectionError as err:
            print(f'[ERROR   ] {format(err)}\n')
            return

        return s3

    def upload_file(self, file_name, s3_object_name):
        """
        Upload a file to an S3 bucket

        :param file_name: Full path to the file to upload
         :type file_name: str
        :param s3_object_name: S3 object name. It should be identical to the LORIS relative path to data_dir
         :type s3_object_name: str
        """

        (s3_bucket_name, s3_bucket, s3_file_name) = self.get_s3_object_path_part(s3_object_name)

        # Upload the file
        try:
            print(f"Uploading {s3_file_name} to {self.aws_endpoint_url}/{s3_bucket_name}")
            s3_bucket.upload_file(file_name, s3_file_name)
        except ClientError as err:
            raise Exception(f"{file_name} upload failure - {format(err)}")

    def upload_dir(self, dir_name, s3_object_name, force = False):
        """
        Upload a directory to an S3 bucket

        :param dir_name: Full path to the dir to upload
         :type dir_name: str
        :param s3_object_name: S3 object name. It should be identical to the LORIS relative path to data_dir
         :type s3_object_name: str
        :param force: Whether to force upload if the file aready exists on the bucket.
         :type force: bool
        """

        (s3_bucket_name, s3_bucket, s3_file_name) = self.get_s3_object_path_part(s3_object_name)

        for (root, dirs, files) in os.walk(dir_name):
            for file in files:
                s3_prefix = os.path.join(s3_file_name, root.replace(dir_name, ""), file)
                s3_dest = os.path.join(
                    's3://',
                    s3_bucket_name,
                    s3_prefix
                )

                """
                If the BIDS data already exists on the destination folder
                delete it first if force is true, otherwise skip it
                """
                if list(s3_bucket.objects.filter(Prefix=s3_prefix)):
                    if not force:
                        print(
                            f"File {s3_dest} already exists. Rerun the script with"
                            f" option --force if you wish to force update the already inserted file."
                        )
                        continue
                    self.delete_file(s3_dest)

                self.upload_file(
                    os.path.join(root, file),
                    s3_dest
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

        (s3_bucket_name, s3_bucket, s3_file_name) = self.get_s3_object_path_part(s3_object_name)

        try:
            print(f"Downloading {s3_file_name} from {self.aws_endpoint_url}/{s3_bucket_name} to {destination_file}")

            for obj in s3_bucket.objects.filter(Prefix=s3_file_name):
                obj_relpath = os.path.relpath(obj.key, s3_file_name)
                target = os.path.join(destination_file, obj_relpath) if obj_relpath != '.' else destination_file

                if not os.path.exists(os.path.dirname(target)):
                    os.makedirs(os.path.dirname(target))
                if obj.key[-1] == '/':
                    continue

                s3_bucket.download_file(obj.key, target)
        except ClientError as err:
            raise Exception(f"{s3_object_name} download failure = {format(err)}")

    def delete_file(self, s3_object_name):
        """
        Function to delete a s3 file or directory.

        :param s3_object_name: name of the s3 file or directory
         :type s3_object_name: str
        """

        print(f"Deleting {s3_object_name}")

        try:
            (s3_bucket_name, s3_bucket, s3_file_name) = self.get_s3_object_path_part(s3_object_name)
            objects_to_delete = [{'Key': obj.key} for obj in s3_bucket.objects.filter(Prefix=s3_file_name)]
            s3_bucket.delete_objects(
                Delete={
                    'Objects': objects_to_delete
                }
            )
        except Exception as err:
            raise Exception(f"{s3_object_name} download failure = {format(err)}")

    def get_s3_object_path_part(self, s3_object_name):
        """
        Function to dissect a s3 file to extract the file prefix and the bucket name

        :param s3_object_name: name of the s3 file or directory
         :type s3_object_name: str
        """

        if not s3_object_name.startswith('s3://'):
            raise Exception(f"{s3_object_name} processing failure, must be a s3 url")

        s3_path_part = s3_object_name.replace('s3://', '').split('/', 1)
        s3_bucket_name = s3_path_part[0]
        s3_bucket = self.s3.Bucket(s3_bucket_name)
        s3_file_name = s3_path_part[1]

        return (s3_bucket_name, s3_bucket, s3_file_name)
