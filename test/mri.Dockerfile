FROM python:3.11

RUN cat /etc/os-release
RUN apt-get update

#####################
# Install utilities #
#####################

# Install the dependencies of LORIS-MRI
RUN apt-get install -y build-essential checkinstall cmake dcmtk dcm2niix libzip-dev mariadb-client perl

# Install utilities
# - `sudo` is used by the imaging install script
# - `wget` is used by some installation commands
RUN apt-get install -y sudo wget

########################
# Install MINC Toolkit #
########################

# Install MINC Toolkit dependencies
RUN apt-get install -y libc6 libstdc++6 imagemagick perl

# Download the MINC Toolkit package
RUN wget -q -P /tmp http://packages.bic.mni.mcgill.ca/minc-toolkit/Debian/minc-toolkit-1.9.18-20200813-Debian_10-x86_64.deb

# Install the MINC Toolkit package
RUN dpkg -i /tmp/minc-toolkit-1.9.18-20200813-Debian_10-x86_64.deb

# Run the MINC Toolkit configuration script
# Usually this would be done with the command `source /opt/minc/1.9.18/minc-toolkit-config.sh`
# However, `source` does not work in Docker, so we set the environment variables manually.
# TODO: Find a way to source the script.
ENV MINC_TOOLKIT=/opt/minc/1.9.18
ENV MINC_TOOLKIT_VERSION="1.9.18-20200813"
ENV PATH=${MINC_TOOLKIT}/bin:${MINC_TOOLKIT}/pipeline:${PATH}
ENV PERL5LIB=${MINC_TOOLKIT}/perl:${MINC_TOOLKIT}/pipeline
ENV LD_LIBRARY_PATH=${MINC_TOOLKIT}/lib:${MINC_TOOLKIT}/lib/InsightToolkit
ENV MNI_DATAPATH=${MINC_TOOLKIT}/../share:${MINC_TOOLKIT}/share
ENV MINC_FORCE_V2=1
ENV MINC_COMPRESS=4
ENV VOLUME_CACHE_THRESHOLD=-1
ENV MANPATH=${MINC_TOOLKIT}/man
ENV ANTSPATH=${MINC_TOOLKIT}/bin

# Download MINC Toolkit auxiliary packages
RUN wget -q -P /tmp https://packages.bic.mni.mcgill.ca/minc-toolkit/Debian/minc-toolkit-testsuite-0.1.3-20131212.deb && \
    wget -q -P /tmp https://packages.bic.mni.mcgill.ca/minc-toolkit/Debian/bic-mni-models-0.1.1-20120421.deb && \
    wget -q -P /tmp https://packages.bic.mni.mcgill.ca/minc-toolkit/Debian/beast-library-1.1.0-20121212.deb

# Install MINC Toolkit auxiliary packages
RUN dpkg -i /tmp/bic-mni-models-0.1.1-20120421.deb && \
    dpkg -i /tmp/bic-mni-models-0.1.1-20120421.deb && \
    dpkg -i /tmp/beast-library-1.1.0-20121212.deb

#####################
# Install LORIS-MRI #
#####################

# Install the Python SQL client extensions
RUN apt-get install -y libmariadb-dev libmariadb-dev-compat

# Install the Perl libraries
# NOTES:
# - not able to install BLAKE2 using a URL so installing it directly with cpanm
COPY install/requirements/cpanfile ./install/requirements/cpanfile
RUN cpan App::cpanminus && \
    cpanm --installdeps ./install/requirements/ && \
    cpanm https://github.com/aces/Loris-MRI/raw/main/install/Digest-BLAKE2-0.02.tar.gz

# Get the database credentials as parameters
ARG DATABASE_NAME
ARG DATABASE_USER
ARG DATABASE_PASS

# Install LORIS-MRI Python
WORKDIR /opt/loris/bin/mri
COPY . .
RUN pip install -e .[dev]

# Run the test LORIS-MRI installer
RUN bash ./test/imaging_install_test.sh $DATABASE_NAME $DATABASE_USER $DATABASE_PASS

# Setup the LORIS-MRI environment variables
ENV PROJECT=loris
ENV MINC_TOOLKIT_DIR=/opt/minc/1.9.18
ENV PATH=/opt/${PROJECT}/bin/mri:/opt/${PROJECT}/bin/mri/uploadNeuroDB:/opt/${PROJECT}/bin/mri/uploadNeuroDB/bin:/opt/${PROJECT}/bin/mri/dicom-archive:/opt/${PROJECT}/bin/mri/python/scripts:/opt/${PROJECT}/bin/mri/tools:/opt/${PROJECT}/bin/mri/python/react-series-data-viewer:${MINC_TOOLKIT_DIR}/bin:/usr/local/bin/tpcclib:$PATH
ENV PERL5LIB=/opt/${PROJECT}/bin/mri/uploadNeuroDB:/opt/${PROJECT}/bin/mri/dicom-archive:$PERL5LIB
ENV TMPDIR=/tmp
ENV LORIS_CONFIG=/opt/${PROJECT}/bin/mri/config
ENV LORIS_MRI=/opt/${PROJECT}/bin/mri
ENV BEASTLIB=${MINC_TOOLKIT_DIR}/../share/beast-library-1.1
ENV MNI_MODELS=${MINC_TOOLKIT_DIR}/../share/icbm152_model_09c

ENTRYPOINT ["./test/entrypoint.sh"]
