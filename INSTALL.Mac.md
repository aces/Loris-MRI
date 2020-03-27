# LORIS-MRI Mac Install Guide

### Mac systems are Not supported for LORIS. 
This guide is offered unofficially on a best-effort basis. 
For best results, we recommend installing LORIS on Ubuntu or CentOS.

This file provides guidance on how to install the imaging pipeline on your Mac computer. LORIS must already be installed.

It has been tested for Mac OS X 10.13. 
Updates and contributions welcome (also see [Contributing Guide](https://github.com/aces/Loris/blob/master/CONTRIBUTING.md)) 

## Get the code

Fork the repository to your GitHub user account.
Then clone this fork on your server as follows (this will create a directory called `mri`) : 

```
sudo mkdir -p /data/$PROJ/bin
cd /data/$PROJ/bin
git clone git@github.com:your-github-username/Loris-MRI.git mri
```
Note: $PROJ = project name. By default we recommend `loris`


## Install [MincToolKit](http://www.bic.mni.mcgill.ca/ServicesSoftware/MINC) and [DCMtk](http://dicom.offis.de/dcmtk.php.en)

## Install PERL libraries
Note: Before compiling `DBD::mysql`, you will need to create some aliases because MySQL on Mac is installed differently than on Linux

```
cd /usr/local
sudo mkdir lib
cd lib
sudo ln -s /usr/local/mysql/lib/*.dylib .
```

```
sudo -S cpan install Math::Round
sudo -S cpan install Getopt::Tabular
sudo -S cpan install Time::JulianDay
sudo -S cpan install Path::Class
sudo -S cpan install DBI
sudo -S cpan install DBD::mysql
sudo -S cpan install Archive::Extract
sudo -S cpan install Archive::Zip
sudo -S cpan install Pod::Perldoc
sudo -S cpan install Pod::Markdown
sudo -S cpan install Pod::Usage
sudo -S cpan install JSON
sudo -S cpan install Moose
sudo -S cpan install MooseX::Privacy
sudo -S cpan install TryCatch
sudo -S cpan install Throwable
```

## Install key Python libraries

- Python dependencies to install 

```
brew install python3
pip install virtualenv
```

- Create the LORIS-MRI virtual python environment 

```
virtualenv /data/$PROJECT/bin/mri/python_virtualenvs/loris-mri-python
```

- Source the `loris-mri-python` virtual environment to install python library dependencies 

```
source /data/$PROJECT/bin/mri/python_virtualenvs/loris-mri-python/bin/activate
```

- Install all python library dependencies

```
pip install mysqlclient
pip install mysql-connector
pip install pybids
pip install pyblake2
pip install mne
pip install google
pip install protobuf
pip install matplotlib
pip install nose
pip install sklearn
pip install nilearn
```

## Install md5sum library

```
brew install md5sha1sum
```

## Install GNU `grep`
 
One of the command run in the insertion pipeline uses a functionality of `grep` that
can only be found in the GNU version of `grep` for Mac. The default installed version
of `grep` in a Mac install does not include the possibility to search based on a 
perl regular expression (option `-P`).
```
brew install grep
```

And add the following to the .bash_profile of the user that will be running the 
pipeline so that the Linux `grep` is used when running the pipeline instead of 
the Mac `grep`.

```
# Add path to linux grep instead of the Mac grep as the Mac one does 
# not have all the functionatities needed by the LORIS imaging pipeline
PATH="/usr/local/opt/grep/libexec/gnubin:$PATH"
```

## Run install script for Mac: imaging_install_MacOSX.sh 

```
cd /data/$PROJ/bin/mri
sh imaging_install_MacOSX.sh
```
Note: $PROJ = project name. By default we recommend `loris`

