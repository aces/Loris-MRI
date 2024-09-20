FROM python:3.11

RUN cat /etc/os-release

RUN apt-get update && \
    apt-get install -y mariadb-client libzip-dev

# Update the package list and install build-essential, checkinstall, and cmake
RUN apt-get update && \
    apt-get install -y build-essential checkinstall cmake

# Install Perl and CPAN
RUN apt-get install -y perl && \
    apt-get install -y libterm-readline-gnu-perl && \
    apt-get install -y perl-doc && \
    apt-get install -y libssl-dev && \
    apt-get install -y liblwp-protocol-https-perl && \
    cpan CPAN

#####################
# Install utilities #
#####################

# Install utilities
# - `wget` is used by some installation commands
# - `sudo` is used by the imaging install script
RUN apt-get install -y wget sudo

# Install the DICOM Toolkit
RUN apt-get install -y dcmtk

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
ENV PERL5LIB=${MINC_TOOLKIT}/perl:${MINC_TOOLKIT}/pipeline${PERL5LIB:+:$PERL5LIB}
ENV LD_LIBRARY_PATH=${MINC_TOOLKIT}/lib:${MINC_TOOLKIT}/lib/InsightToolkit${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
ENV MNI_DATAPATH=${MINC_TOOLKIT}/../share:${MINC_TOOLKIT}/share
ENV MINC_FORCE_V2=1
ENV MINC_COMPRESS=4
ENV VOLUME_CACHE_THRESHOLD=-1
ENV MANPATH=${MINC_TOOLKIT}/man${MANPATH:+:$MANPATH}
ENV ANTSPATH=${MINC_TOOLKIT}/bin

# Download MINC Toolkit auxiliary packages
RUN wget -q -P /tmp https://packages.bic.mni.mcgill.ca/minc-toolkit/Debian/minc-toolkit-testsuite-0.1.3-20131212.deb
RUN wget -q -P /tmp https://packages.bic.mni.mcgill.ca/minc-toolkit/Debian/bic-mni-models-0.1.1-20120421.deb
RUN wget -q -P /tmp https://packages.bic.mni.mcgill.ca/minc-toolkit/Debian/beast-library-1.1.0-20121212.deb

# Install MINC Toolkit auxiliary packages
RUN dpkg -i /tmp/bic-mni-models-0.1.1-20120421.deb
RUN dpkg -i /tmp/bic-mni-models-0.1.1-20120421.deb
RUN dpkg -i /tmp/beast-library-1.1.0-20121212.deb

#####################
# Install LORIS-MRI #
#####################

# Install the Python SQL client extensions
RUN apt-get install -y libmariadb-dev libmariadb-dev-compat

# Install the Perl libraries
RUN cpan install Math::Round
RUN cpan install DBI
RUN cpan install DBD::mysql@4.052
RUN cpan install Getopt::Tabular
RUN cpan install Time::JulianDay
RUN cpan install Path::Class
RUN cpan install Archive::Extract
RUN cpan install Archive::Zip
RUN cpan install Pod::Perldoc
RUN cpan install Pod::Markdown
RUN cpan install Pod::Usage
RUN cpan install JSON
RUN cpan install Moose
RUN cpan install MooseX::Privacy
RUN cpan install TryCatch
RUN cpan install Throwable
RUN cpan install App::cpanminus
RUN cpanm https://github.com/aces/Loris-MRI/raw/main/install/Digest-BLAKE2-0.02.tar.gz
RUN cpan install File::Type
RUN cpan install String::ShellQuote
RUN cpan install DateTime

# Install the Python libraries
COPY python/requirements.txt ./python/requirements.txt
RUN pip install --no-cache-dir -r ./python/requirements.txt

# Checkout the LORIS-MRI repository
COPY . /opt/loris/bin/mri
WORKDIR /opt/loris/bin/mri
RUN bash ./test/imaging_install_test.sh

# Setup the LORIS-MRI environment variables
ENV PROJECT=loris
ENV MINC_TOOLKIT_DIR=/opt/minc/1.9.18
ENV PATH=/opt/${PROJECT}/bin/mri:/opt/${PROJECT}/bin/mri/uploadNeuroDB:/opt/${PROJECT}/bin/mri/uploadNeuroDB/bin:/opt/${PROJECT}/bin/mri/dicom-archive:/opt/${PROJECT}/bin/mri/python:/opt/${PROJECT}/bin/mri/tools:/opt/${PROJECT}/bin/mri/python/react-series-data-viewer:${MINC_TOOLKIT_DIR}/bin:/usr/local/bin/tpcclib:$PATH
ENV PERL5LIB=/opt/${PROJECT}/bin/mri/uploadNeuroDB:/opt/${PROJECT}/bin/mri/dicom-archive:$PERL5LIB
ENV TMPDIR=/tmp
ENV LORIS_CONFIG=/opt/${PROJECT}/bin/mri/dicom-archive
ENV LORIS_MRI=/opt/${PROJECT}/bin/mri
ENV PYTHONPATH=$PYTHONPATH:/opt/${PROJECT}/bin/mri/python:/opt/${PROJECT}/bin/mri/python/react-series-data-viewer
ENV BEASTLIB=${MINC_TOOLKIT_DIR}/../share/beast-library-1.1
ENV MNI_MODELS=${MINC_TOOLKIT_DIR}/../share/icbm152_model_09c
