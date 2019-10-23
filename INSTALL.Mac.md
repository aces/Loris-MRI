#LORIS-MRI Mac Install Guide
### Mac is no longer supported as of 15.10. 

This is a guide on how to install the imaging pipeline on your Mac computer. It has been tested for Mac OS X 10.13.
For best results, we recommend installing LORIS on Ubuntu or CentOS.

## Grep the code from Github

Request Loris-MRI Github repository permission. 
Fork the repository to your Git-user and clone the fork to your server.

```
sudo mkdir -p /data/$PROJ/bin
cd /data/$PROJ/bin
git clone git@github.com:your-git-username/Loris-MRI.git mri
```
Note: $PROJ = project name


## 3. Install [minctoolkit](http://www.bic.mni.mcgill.ca/ServicesSoftware/MINC) and [dcmtk] (http://dicom.offis.de/dcmtk.php.en)

## 4. Install the following perl libraries
Note: Before compiling DBD::mysql, you will need to create some alias because MySQL on Mac is installed differently than on Linux

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

## 5. Install the following python libraries

- Python dependencies to install 

```
brew install python3
pip install virtualenv
```

- Creation of the LORIS-MRI virtual python environment 

```
virtualenv /data/$PROJECT/bin/mri/python_virtualenvs/loris-mri-python
```

- Source the loris-mri-python virtual environment to install all python library dependencies 

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

## 6. Install md5sum library

```
brew install md5sha1sum
```

## 7. Run imaging_install_MacOSX.sh script

```
sh imaging_install_MacOSX.sh
```

