ARG PYTHON_VERSION=3.11

FROM python:${PYTHON_VERSION}-slim

RUN pip install boto3
RUN pip install google
RUN pip install mat73
RUN pip install matplotlib
RUN pip install mne
RUN pip install mne-bids>=0.6
RUN pip install mysql-connector
RUN pip install mysqlclient
RUN pip install nilearn
RUN pip install nibabel
RUN pip install nose
RUN pip install numpy
RUN pip install protobuf>=3.0.0
RUN pip install pybids==0.17.0
RUN pip install pyright
RUN pip install pytest
RUN pip install python-dateutil
RUN pip install ruff
RUN pip install scikit-learn
RUN pip install scipy
RUN pip install sqlalchemy>=2.0.0
RUN pip install virtualenv
