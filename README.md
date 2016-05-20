# System Requirements
 * Perl
 * DICOM toolkit (step 4)
 * MINC toolkit (step 3)

Note: For Ubuntu installations, DICOM toolkit will be installed by the imaging install script (see step 4 below). This script will apt-get install dcmtk.   

The following installation should be run by the $lorisadmin user. sudo permission is required.
See aces/Loris README.md for further information and Loris installation information. 

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

   Pre-compiled packages are available for major operating systems.

4. Run installer to install DICOM toolkit, Perl libraries, configure environment, and setup directories:

   ```bash 
   cd /data/$projectname/bin/mri/
   ./imaging_install.sh
   ```

  You will be asked for the following input: 

 * What is the database name? $dbname
 * What is the database host? $dbhost
 * What is the MySQL user? $lorisuser 
 * What is the MySQL password? 
 * What is the Linux user which the installation will be based on? $lorisadmin
 * What is the project name? $projectname
 * What is your email address? 
 * What prod file name would you like to use? default: prod  [leave blank]
 * Enter the list of Site names (space separated) site1 site2

  If the imaging install script reports errors in creating directories (due to /data/ mount permissions), manually execute mkdir and chmod commands starting at [imaging_install.sh:L90](https://github.com/aces/Loris-MRI/blob/master/imaging_install.sh#L90)

5. Configure paths and environment

   Ensure that /home/$lorisadmin/.bashrc includes the statement: 

   ```source /data/$projectname/bin/mri/environment```

   Ensure that the apache envvars file includes all the EXPORT statements from minc-toolkit-config.sh (this file located in the path where the MINC tools are installed). This is necessary for BrainBrowser to successfully load MINC images.

   Finally, source the .bashrc file and restart apache.


Installation complete. For customizations and protocol configurations, see [LORIS Imaging Setup Guide](https://github.com/aces/Loris/wiki/Imaging-Database).

