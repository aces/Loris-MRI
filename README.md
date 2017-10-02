This Readme covers release 18.0 of the LORIS Imaging Insertion Pipeline for Ubuntu or CentOS systems

This repo accompanies the [LORIS neuroimaging data platform main repo](https://github.com/aces/Loris/releases)</b>, release 18.0.*.<br>
For documentation and detailed setup information, please see the [LORIS wiki](https://github.com/aces/Loris/wiki/Imaging-Database)</b>.

This repo can be installed on the same VM as the main LORIS codebase, or on a different machine such as a designated fileserver where large imaging filesets are to be stored. 

# System Requirements
 * Perl
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

#### 2. Install dicom-archive-tools sub-repo within the mri/ directory (created by the git clone command):

   ```bash
   cd /data/$projectname/bin/mri/
   git submodule init
   git submodule sync
   git submodule update
   ```

#### 3. Install MINC toolkit from http://bic-mni.github.io/ 

Download the pre-compiled package for your operating system.  Install required dependencies such as _imagemagick_. Then install your MINC toolkit package: 

   ```bash
   sudo dpkg -i minc-toolkit<version>.deb
   ```

  Then source the MINC toolkit environment by running (for bash) `source /opt/minc/minc-toolkit-config.sh` or (tcsh) `source /opt/minc/minc-toolkit-config.csh`.

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

  To help ensure Apache-writability, verify that your environment file contains the following line:

   ```bash 
   umask 0002
   ```

   Ensure that /home/lorisadmin/.bashrc includes the statement: 

   ```source /data/$projectname/bin/mri/environment```

   Then source the .bashrc file.   

#### 6. Set up MINC utilities for BrainBrowser visualization

To ensure that BrainBrowser can load MINC images, the MINC toolkit must be accessible to the main LORIS codebase.
(If the Loris-MRI codebase is installed on a separate machine, ensure the MINC toolkit is installed in both locations.)

Ensure the _project/config.xml_ file (in the main LORIS codebase) contains the following tagset, specifying the MINC toolkit path local to the main LORIS codebase (/opt/minc/ in this example):

   ```xml
   <!-- MINC TOOLS PATH -->
   <MINCToolsPath>/opt/minc/</MINCToolsPath>
   ```

#### 7. Verify filesystem permissions 

Ensure that permissions on /data/$projectname and /data/incoming and their subdirectories are set such that lorisadmin and the Apache linux user can read, write _and_ execute all contents.

The following must be recursively owned by the lorisadmin user and by Apache group:

   ```bash
   /data/$projectname/data/ 
   /data/$projectname/bin/mri/
   /data/incoming/
   /data/$projectname/bin/mri/dicom-archive/.loris_mri/prod
   ```
#### 8. Verify Configuration module settings for Imaging Pipeline
  
In the LORIS front-end, under the Admin menu, go to the `Config` module.  Under the section `Imaging Pipeline`, verify/set the following config settings: 
 * `Loris-MRI Data Directory`
 * `Study Name`
 * `User to notify when executing the pipeline`
 * `Full path to get_dicom_info.pl script`
 * `Path to Tarchives`

Click 'Submit' at the end of the Configuration page to save any changes. 

<br>
Installation complete.

For customizations and protocol configurations, see LORIS Imaging Setup Guide : https://github.com/aces/Loris/wiki/Imaging-Database 

