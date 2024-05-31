This Readme covers release 24.1.* of the LORIS Imaging Insertion Pipeline for Ubuntu or CentOS systems

This repo accompanies the [LORIS neuroimaging data platform main repo](https://github.com/aces/Loris/releases)</b>, release 24.1.*.<br>
For documentation and detailed setup information, please see the [LORIS-MRI documentation](docs/) for your installed version</b>.

This repo can be installed on the same VM as the main LORIS codebase, or on a different machine such as a designated fileserver where large imaging filesets are to be stored. 

# System Requirements

* Perl
* Python 3 with pip3 and virtualenv (step 2 below)
* MINC toolkit (step 3 below)
* DICOM toolkit (step 4 below)
* tpcclib (for HRRT PET only) (step 5 below)

On <u>Ubuntu</u>, DICOM toolkit will be installed by the imaging install script (step 4 below). This script will _apt-get install dcmtk_.   

For <u>CentOS</u>: The [LORIS wiki](https://github.com/aces/Loris/wiki/Imaging-Database) Imaging setup page (see Section 1, installing codebase) includes links to older transcripts for [CentOS installation](https://github.com/aces/Loris/wiki/CentOS-Imaging-installation-transcript) and notes on dependencies including [DICOM toolkit](https://github.com/aces/Loris/wiki/CentOS-Imaging-installation-transcript#7-install-dicom-toolkit).

The following installation should be run by the `$lorisadmin` user. `sudo` permission is required.
See [aces/Loris](https://github.com/aces/loris) README.md for further information. 

# Dependencies

## General

```bash
# ubuntu build essential packages useful for building
sudo apt install build-essential checkinstall cmake
```

## Perl CPAN

Update Perl dependency with:

```bash
sudo perl -MCPAN -e shell

# then enter these two commands

cpan[1]> install CPAN
cpan[2]> reload cpan
```

# Installation

#### 1. Create directories and download Loris-MRI code

```bash
sudo mkdir -p /data/$projectname
sudo mkdir -p /opt/$projectname/bin/mri
sudo chown -R lorisadmin:lorisadmin /data/$projectname
sudo chown -R lorisadmin:lorisadmin /opt/$projectname
cd /opt/$projectname/bin
```

Get the code: Download the latest release from the 
[releases page](https://github.com/aces/Loris-MRI/releases) 
and extract it to `/opt/$projectname/bin/mri`

#### 2. Install Python 3 with `pip` and `virtualenv`

```bash
sudo apt install python3 
sudo apt install python3-dev
sudo apt install python3-pip
sudo apt install libmysqlclient-dev
sudo apt install virtualenv
```

#### 3. Install MINC toolkit from http://bic-mni.github.io/ 

- Install MINC dependencies:

```bash
# deps
sudo apt-get install libc6 libstdc++6 imagemagick perl

# Install required dependencies such as _imagemagick_.
sudo apt-get install libgl1-mesa-glx libglu1-mesa
```

- Download the MINC pre-compiled package for your operating system from http://bic-mni.github.io/.

- Then install the MINC toolkit package: 

```bash
# main minc lib
sudo dpkg -i minc-toolkit-<version>.deb
```

- Check the model is installed in `/opt/minc/share`

- Then source the MINC toolkit environment, where `$mincToolsDirectory` is the path where the MINC toolkit is installed (e.g. `/opt/minc/` OR `/opt/minc/$mincToolsVersion/` for more recent installs)

```bash
# bash
source $mincToolsDirectory/minc-toolkit-config.sh

# tcsh
source $mincToolsDirectory/minc-toolkit-config.csh
```

- For the defacing scripts, you will also need to download the pre-compiled `bic-mni-models` and `beast` data and model packages for you operation system.

```bash
sudo dpkg -i bic-mni-models-<version>.deb
sudo dpkg -i beast-library-<version>.deb

# also check they are installed in `/opt/minc/share`
```

#### 4. Run installer to set up directories, configure environment, install Perl libraries and DICOM toolkit:

```bash 
cd /opt/$projectname/bin/mri/install/
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

If the imaging install script reports errors in creating directories 
(due to `/data/` mount permissions), review and manually execute 
`mkdir/chmod/chown` commands starting at 
[imaging_install.sh:L97](https://github.com/aces/Loris-MRI/blob/main/install/imaging_install.sh#L97)

Note: The installer will allow Apache to write to the `/data/` and `/opt/` directories by 
adding user `lorisadmin` to the Apache linux group.  To ensure this change takes 
effect, log out and log back into your terminal session before running the 
imaging pipeline. The installer will also set Apache group ownership of certain 
`/data/` and `/opt/` subdirectories.

#### 5. HRRT PET

For HRRT PET, install [tpcclib](http://www.turkupetcentre.net/tpcclib-doc/md_install.html).
Follow the [install instructions](http://www.turkupetcentre.net/petanalysis/sw_install.html).

#### 6. Configure paths and environment

Ensure that `/home/lorisadmin/.bashrc` includes the statement:

```bash
source /opt/$projectname/bin/mri/environment
```

Then source the `.bashrc` file.


**INSTALLATION COMPLETE!**

Please refer to the [Install](docs/02-Install.md) section in the 
[LORIS-MRI documentation](docs/) for your installed version for:
- customizations and protocol configurations ([Section 2.2](docs/02-Install.md#configuration)).
- verifying that certain fields were correctly populated by `imaging_install.sh`
([Section 2.3](docs/02-Install.md#post-installation-checks)).


