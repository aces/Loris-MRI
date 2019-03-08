This Readme covers release 20.1 of the LORIS Imaging Insertion Pipeline for Ubuntu or CentOS systems

This repo accompanies the [LORIS neuroimaging data platform main repo](https://github.com/aces/Loris/releases)</b>, release 20.1.*.<br>
For documentation and detailed setup information, please see the [LORIS-MRI documentation](docs/) for your installed version</b>.

This repo can be installed on the same VM as the main LORIS codebase, or on a different machine such as a designated fileserver where large imaging filesets are to be stored. 

# System Requirements
 * Perl
 * Python 3 with pip3 and virtualenv (step 2 below)
 * MINC toolkit (step 3 below)
 * DICOM toolkit (step 4 below)

On <u>Ubuntu</u>, DICOM toolkit will be installed by the imaging install script (step 4 below). This script will _apt-get install dcmtk_.   

For <u>CentOS</u>: The [LORIS wiki](https://github.com/aces/Loris/wiki/Imaging-Database) Imaging setup page (see Section 1, installing codebase) includes links to older transcripts for [CentOS installation](https://github.com/aces/Loris/wiki/CentOS-Imaging-installation-transcript) and notes on dependencies including [DICOM toolkit](https://github.com/aces/Loris/wiki/CentOS-Imaging-installation-transcript#7-install-dicom-toolkit).

The following installation should be run by the $lorisadmin user. sudo permission is required.
See [aces/Loris](https://github.com/aces/loris) README.md for further information. 

# Installation

#### 1. Create directories and download Loris-MRI code

   ```bash
   sudo mkdir -p /data/$projectname/bin/mri
   sudo chown -R lorisadmin:lorisadmin /data/$projectname
   cd /data/$projectname/bin
   git clone -b master https://github.com/aces/Loris-MRI.git mri
   ```

#### 2. Install Python 3 with `pip` and `virtualenv`

```bash
sudo apt-get install python3 
sudo apt-get install python3-dev
sudo apt-get install python3-pip
sudo apt-get install libmysqlclient-dev
sudo pip3 install virtualenv
```

#### 3. Install MINC toolkit from http://bic-mni.github.io/ 

Download the pre-compiled package for your operating system.  Install required dependencies such as _imagemagick_. Then install your MINC toolkit package: 

   ```bash
   sudo dpkg -i minc-toolkit<version>.deb
   ```

  Then source the MINC toolkit environment by running (for bash)
  `source $mincToolsDirectory/minc-toolkit-config.sh` or (tcsh)
  `source $mincToolsDirectory/minc-toolkit-config.csh`,

  where `$mincToolsDirectory` is the path where the MINC toolkit is installed (e.g. `/opt/minc/` OR `/opt/minc/$mincToolsVersion/` for more recent installs)

For the defacing scripts, you will also need to download the pre-compiled `bic-mni-models` and `beast` data and model packages for you operation system.

   ```bash
   sudo dpkg -i bic-mni-models-<version>.deb
   sudo dpkg -i beast-library-<version>.deb
   ```

#### 4. Run installer to set up directories, configure environment, install Perl libraries and DICOM toolkit:

   ```bash 
   cd /data/$projectname/bin/mri/
   bash ./imaging_install.sh
   ```

  You will be asked for the following input: 

 * What is the database name? $dbname
 * What is the database host? $dbhost
 * What is the MySQL user? $lorisuser [Use the same mysql user from the Loris installation, i.e. _lorisuser_]
 * What is the MySQL password? 
 * What is the Linux user which the installation will be based on? $lorisadmin
 * What is the project name? $projectname
 * What is your email address? 
 * What prod file name would you like to use? default: prod  [leave blank]
 * Enter the list of Site names (space separated) site1 site2

  If the imaging install script reports errors in creating directories (due to /data/ mount permissions), review and manually execute `mkdir/chmod/chown` commands starting at [imaging_install.sh:L97](https://github.com/aces/Loris-MRI/blob/master/imaging_install.sh#L97)

  Note: The installer will allow Apache to write to the /data/ directories by adding user lorisadmin to the Apache linux group.  To ensure this change takes effect, log out and log back into your terminal session before running the imaging pipeline.
The installer will also set Apache group ownership of certain /data/ subdirectories.

#### 5. Configure paths and environment

   Ensure that /home/lorisadmin/.bashrc includes the statement:

   ```source /data/$projectname/bin/mri/environment```

   Then source the .bashrc file.   

**INSTALLATION COMPLETE!**

Please refer to the [Install](docs/02-Install.md) section in the 
[LORIS-MRI documentation](docs/) for your installed version for:
- customizations and protocol configurations ([Section 2.2](docs/02-Install.md#configuration)).
- verifying that certain fields were correctly populated by `imaging_install.sh`
([Section 2.3](docs/02-Install.md#post-installation-checks)).


