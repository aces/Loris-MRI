This Readme covers release 16.0 of the LORIS Imaging Insertion Pipeline for Ubuntu or CentOS systems

This repo accompanies the [LORIS neuroimaging data platform main repo](https://github.com/aces/Loris)</b>.<br>
For documentation and detailed setup information, please see the [LORIS wiki](https://github.com/aces/Loris/wiki/Imaging-Database)</b>.

This repo can be installed on either the same VM as the main LORIS codebase, or on a different machine such as a designated fileserver where large imaging filesets are to be stored. 

# System Requirements
 * Perl
 * DICOM toolkit (step 4)
 * MINC toolkit (step 3)

Note: For Ubuntu installations, DICOM toolkit will be installed by the imaging install script (see step 4 below). This script will _apt-get install dcmtk_.   

The following installation should be run by the $lorisadmin user. sudo permission is required.
See [aces/Loris README.md](https://github.com/aces/loris) for further information and Loris installation information. 

# Installation

1. Create directories

   ```bash
   sudo mkdir -p /data/$projectname/bin/mri
   sudo chown -R lorisadmin:lorisadmin /data/$projectname
   cd /data/$projectname/bin
   git clone https://github.com/aces/Loris-MRI.git mri
   ```
   
2. Install dicom-archive-tools sub-repo within the mri/ directory (created by the git clone command):

   ```bash
   cd /data/$projectname/bin/mri/
   git submodule init
   git submodule sync
   git submodule update
   ```

3. Install MINC toolkit from http://bic-mni.github.io/ 

   Pre-compiled packages are available for major operating systems. Note required dependencies such as imagemagick.

4. Run installer to install DICOM toolkit, Perl libraries, configure environment, and setup directories:

   ```bash 
   cd /data/$projectname/bin/mri/
   ./imaging_install.sh
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

  If the imaging install script reports errors in creating directories (due to /data/ mount permissions), manually execute mkdir and chmod commands starting at [imaging_install.sh:L90](https://github.com/aces/Loris-MRI/blob/16.0-dev/imaging_install.sh#L90)

  The installer will make lorisadmin part of apache (or www-data) linux group.  

5. Configure paths and environment

   Ensure that /home/$lorisadmin/.bashrc includes the statement: 

   ```source /data/$projectname/bin/mri/environment```

   Then source the .bashrc file.   
   Also ensure that the apache envvars file includes all the EXPORT statements from minc-toolkit-config.sh (file located in the path where the MINC toolkit is installed), then restart apache.

6. Set up MINC utilities for BrainBrowser visualization

   To ensure that BrainBrowser can load MINC images, the MINC toolkit must be accessible to the main LORIS codebase.
   (If the Loris-MRI codebase is installed on a separate machine, ensure the MINC toolkit is installed in both locations.)

   Ensure the _project/config.xml_ file (in the main LORIS codebase) contains the following tagset, specifying the MINC toolkit path local to the main LORIS codebase (/opt/minc/ in this example):


   ```xml
   <!-- MINC TOOLS PATH -->
   <MINCToolsPath>/opt/minc/</MINCToolsPath>
   ```

<br>
   Installation complete. For customizations and protocol configurations, see [LORIS Imaging Setup Guide](https://github.com/aces/Loris/wiki/Imaging-Database).

