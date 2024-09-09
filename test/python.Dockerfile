# This is a minimal Docker image to run static tests on the Python code of LORIS-MRI.
# It sets up Python and our Python dependencies, but does not configure a full setup
# to test LORIS-MRI (Perl code, database...).

ARG PYTHON_VERSION=3.11

FROM python:${PYTHON_VERSION}-slim

# Required for the Python library `mysqlclient`
RUN apt-get update
RUN apt-get install -y default-libmysqlclient-dev build-essential pkg-config

COPY ./python/requirements.txt requirements.txt

RUN pip install -r requirements.txt
