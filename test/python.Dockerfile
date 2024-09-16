# This is a minimal Docker image to run static tests on the Python code of LORIS-MRI.
# It sets up Python and our Python dependencies, but does not configure a full setup
# to test LORIS-MRI (Perl code, database...).

# Python version to use for the tests
ARG PYTHON_VERSION=3.11

FROM python:${PYTHON_VERSION}-slim

# Path of the LORIS-MRI repository in the container
ARG WORKSPACE

RUN apt-get update

# Required for the Python library `mysqlclient`
RUN apt-get install -y default-libmysqlclient-dev build-essential pkg-config

# Used to format the Pyright errors to the GitHub format
RUN apt-get install -y jq

COPY ./python/requirements.txt requirements.txt

RUN pip install --no-cache-dir --root-user-action=ignore -r requirements.txt

ENV PYTHONPATH=${WORKSPACE}/python:${WORKSPACE}/python/react-series-data-viewer
