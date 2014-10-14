# System Requirements
 * DICOM toolkit
 * Perl
 * MINC

# Installation

1. Create directories

   ```bash
   sudo mkdir -p /data/$projectname/bin
   sudo chown -R lorisadmin:lorisadmin /data/$projectname
   cd /data/$projectname/bin
   git clone git@github.com:your-git-username/Loris-MRI.git mri
   ```
   
2. Install Dicom-archive within the mri/ directory (created by the git clone command):

   ```bash
   cd /data/$projectname/bin/mri/
   git submodule init
   git submodule sync
   git submodule update
   ```

3. Run installer to install MINC & DICOM toolkits, Perl libraries, configure environment, and setup directories:

   ```bash imaging_install.sh```

  You will be asked for the following input: 

 * What is the database name? $dbname
 * What is the database host? $dbhost
 * What is the Mysql user? $lorisuser 
 * What is the mysql password? 
 * What is the linux user which the installation will be based on? $lorisadmin
 * What is the project Name $projectname
 * What is your email address 
 * What prod file name would you like to use? default: prod?”  [leave blank]
 * Enter the list of Site names (space separated) site1 site2

Ensure that /home/lorisadmin/.bashrc includes the statements: 

```source /data/$projectname/bin/mri/environment```

Installation complete. For customizations & protocol configurations, see LORIS Developer’s Guide.
