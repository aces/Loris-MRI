#LORIS-MRI Mac Install Guide
### Mac is no longer supported as of 15.10. 

This is a guide on how to install the imaging pipeline on your Mac computer. It has been tested for Mac OS X 10.9.
For best results, we recommend installing LORIS on Ubuntu or CentOS.

## 1. Grep the code from Github

Request Loris-MRI Github repository permission. 
Fork the repository to your Git-user and clone the fork to your server.

```
sudo mkdir -p /data/$PROJ/bin
sudo chown -R lorisadmin:lorisadmin /data/$PROJ
cd /data/$PROJ/bin
git clone git@github.com:your-git-username/Loris-MRI.git mri
```
Note: $PROJ = project name

## 2. Install Dicom-archive within the mri/ directory

```
cd /data/$PROJ/bin/mri/
git submodule init
git submodule sync
git submodule updatemo9
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
```

## 5. Install md5sum library

```
sudo port install md5sh1sum
```

## 6. Run imaging_install_MacOSX.sh script

```
sh imaging_install_MacOSX.sh
```

