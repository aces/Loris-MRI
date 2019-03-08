#!/bin/bash

##################################
###WHAT THIS SCRIPT WILL NOT DO###
#1)It doesn't set up the SGE
#2)It doesn't fetch the CIVET stuff   TODO:Get the CIVET stuff from somewhere and place it in somewhere
#3)It doesn't change the config.xml
#4)It doesn't populate the Config tables with paths etc.
##################################

#Create a temporary log for installation and delete it on completion 
#@TODO make sure that /tmp is writable
LOGFILE="/tmp/$(basename $0).$$.tmp"
touch $LOGFILE
trap "rm  $LOGFILE" EXIT
 
if [[ -n $(which mincheader) ]]; then
    echo ""
    echo "MINC Toolkit appears to be installed."
else
    echo ""
    echo "MINC Toolkit does not appear to be installed. Please see http://www.bic.mni.mcgill.ca/ServicesSoftware/MINC. Aborting."
    exit 2;
fi
MINC_TOOLKIT_DIR=`which mincheader|sed s#/bin/mincheader##`

#First, check that all required modules are installed.
#Check if cpan module installed
CPANCHECK=`which cpan`
if [ ! -f "$CPANCHECK" ]; then
    echo "\nERROR: Unable to find cpan"
    echo "Please ask your sysadmin or install cpan\n"
    exit
fi
#Check if make is installed
MAKECHECK=`which make`
if [ ! -f "$MAKECHECK" ]; then
    echo "\nERROR: Unable to find make"
    echo "Please ask your sysadmin or install make\n"
    exit
fi

read -p "What is the database name? " mysqldb
read -p "What is the database host? " mysqlhost
read -p "What is the MySQL user? " mysqluser
stty -echo
read -p "What is the MySQL password? " mysqlpass; echo
stty echo
read -p "What is the Linux user which the installation will be based on? " USER
read -p "What is the project name? " PROJ   ##this will be used to create all the corresponding directories...i.e /data/gusto/bin.....
read -p "What is your email address? " email
read -p "What prod file name would you like to use? default: prod " prodfilename
if [ -z "$prodfilename" ]; then
    prodfilename="prod"
fi 
 
read -p "Enter the list of Site names (space separated) " site
mridir=`pwd`
#read -p "Enter Full Loris-code directory path "   lorisdir


#################################################################################################
############################INSTALL THE PERL LIBRARIES###########################################
#################################################################################################
echo "Installing the perl libraries...This will take a few minutes..."
#echo $rootpass | sudo perl -MCPAN -e shell
sudo -S cpan install Math::Round
#echo $rootpass | sudo -S cpan install Bundle::CPAN
sudo -S cpan install Getopt::Tabular
sudo -S cpan install Time::JulianDay
sudo -S cpan install Path::Class
sudo -S cpan install Archive::Extract
sudo -S cpan install Archive::Zip
sudo -S cpan install Pod::Perldoc
sudo -S cpan install Pod::Markdown
sudo -S cpan install Pod::Usage
sudo -S cpan install JSON
echo

################################################################################
##Create the loris-mri python virtualenv and install the Python packages########
################################################################################
echo "Creating loris-mri Python virtualenv in $mridir/python_virtualenvs/loris-mri-python/"
# create a directory in $mridir that will store python 3 virtualenv
sudo -S su $USER -c "mkdir -m 770 -p $mridir/python_virtualenvs/loris-mri-python"
virtualenv $mridir/python_virtualenvs/loris-mri-python -p `which python3`
source $mridir/python_virtualenvs/loris-mri-python/bin/activate
echo "Installing the Python libraries into the loris-mri virtualenv..."
pip3 install mysqlclient
pip3 install mysql-connector
pip3 install pybids
pip3 install pyblake2
pip3 install mne
pip3 install google
pip3 install protobuf
# deactivate the virtualenv for now
deactivate

#######################################################################################
#############################Create directories########################################
#######################################################################################
echo "Creating the data directories"
  sudo -S su $USER -c "mkdir -m 2770 -p /data/$PROJ/data/"
  sudo -S su $USER -c "mkdir -m 770 -p /data/$PROJ/data/trashbin"         #holds mincs that didn't match protocol
  sudo -S su $USER -c "mkdir -m 770 -p /data/$PROJ/data/tarchive"         #holds tared dicom-folder
  sudo -S su $USER -c "mkdir -m 770 -p /data/$PROJ/data/pic"              #holds jpegs generated for the MRI-browser
  sudo -S su $USER -c "mkdir -m 770 -p /data/$PROJ/data/logs"             #holds logs from pipeline script
  sudo -S su $USER -c "mkdir -m 770 -p /data/$PROJ/data/assembly"         #holds the MINC files
  sudo -S su $USER -c "mkdir -m 770 -p /data/$PROJ/data/batch_output"     #contains the result of the SGE (queue)
  sudo -S su $USER -c "mkdir -m 770 -p /data/$PROJ/data/bids_imports"     #contains imported BIDS studies
  sudo -S su $USER -c "mkdir -m 770 -p $mridir/dicom-archive/.loris_mri"
echo

#####################################################################################
###############incoming directory ###################################################
#####################################################################################
sudo -S su $USER -c "mkdir -m 2770 -p /data/incoming/"

###################################################################################
#######set environment variables under .bashrc#####################################
###################################################################################
echo "Modifying environment script"
sed -i "s#%PROJECT%#$PROJ#g" $mridir/environment
sed -i "s#%MINC_TOOLKIT_DIR%#$MINC_TOOLKIT_DIR#g" $mridir/environment
#Make sure that CIVET stuff are placed in the right place
#source /data/$PROJ/bin/$mridirname/environment
export TMPDIR=/tmp
echo

####################################################################################
######################Add the proper Apache group user #############################
####################################################################################
if egrep ^www-data: /etc/group > $LOGFILE 2>&1;
then 
    group=www-data
elif egrep ^www: /etc/group  > $LOGFILE 2>&1;
then
    group=www
elif egrep -e ^apache: /etc/group  > $LOGFILE 2>&1;
then
    group=apache
else
    read -p "Cannot find the apache group name for your installation. Please provide? " group
fi

####################################################################################
######################change permissions ###########################################
####################################################################################
#echo "Changing permissions"

sudo chmod -R 770 $mridir/dicom-archive/.loris_mri/
sudo chmod -R 770 /data/$PROJ/
sudo chmod -R 770 /data/incoming/

# Making lorisadmin part of the apache group
sudo usermod -a -G $group $USER

#Setting group permissions for all files/dirs under /data/$PROJ/ and /data/incoming/
sudo chgrp $group -R /data/$PROJ/
sudo chgrp $group -R /data/incoming/

#Setting group ID for all files/dirs under /data/$PROJ/data
sudo chmod -R g+s /data/$PROJ/data/

#Setting group ID for all files/dirs under /data/incoming
sudo chmod -R g+s /data/incoming/
echo

#####################################################################################
##########################change the prod file#######################################
#####################################################################################
echo "Creating MRI config file"

cp $mridir/dicom-archive/profileTemplate $mridir/dicom-archive/.loris_mri/$prodfilename
sudo chmod 640 $mridir/dicom-archive/.loris_mri/$prodfilename
sudo chgrp $group $mridir/dicom-archive/.loris_mri/$prodfilename

sed -e "s#DBNAME#$mysqldb#g" -e "s#DBUSER#$mysqluser#g" -e "s#DBPASS#$mysqlpass#g" -e "s#DBHOST#$mysqlhost#g" $mridir/dicom-archive/profileTemplate > $mridir/dicom-archive/.loris_mri/$prodfilename
echo "config file is located at $mridir/dicom-archive/.loris_mri/$prodfilename"
echo

echo "Creating python database config file with database credentials"
cp $mridir/dicom-archive/database_config_template.py $mridir/dicom-archive/.loris_mri/database_config.py
sudo chmod 640 $mridir/dicom-archive/.loris_mri/database_config.py
sudo chgrp $group $mridir/dicom-archive/.loris_mri/database_config.py
sed -e "s#DBNAME#$mysqldb#g" -e "s#DBUSER#$mysqluser#g" -e "s#DBPASS#$mysqlpass#g" -e "s#DBHOST#$mysqlhost#g" $mridir/dicom-archive/database_config_template.py > $mridir/dicom-archive/.loris_mri/database_config.py
echo "config file for python import scripts is located at $mridir/dicom-archive/.loris_mri/database_config.py"
echo

######################################################################
###########Modify the config.xml######################################
######################################################################
#sed -i "s#SAME AS imagePath#/data/$PROJ/data#g" -i "s#/PATH/TO/MINC/DATA/ROOT/mri-data/minc/#data/$PROJ/data#g" $lorisdir/project/config.xml

################################################################################################
#####################################DICOM TOOLKIT##############################################
################################################################################################
os_distro=$(lsb_release -si)
if [ $os_distro  = "CentOS" ]; then
    echo "You are running CentOS. Please also see Loris-MRI Readme for notes and links to further documentation in our main GitHub Wiki on how to install the DICOM Toolkit and other required dependencies."
else
    #Check if apt-get is install
    APTGETCHECK=`which apt-get`
    if [ ! -f "$APTGETCHECK" ]; then
        echo "\nERROR: Unable to find apt-get"
        echo "Please ask your sysadmin or install apt-get\n"
        exit
    fi

    echo "Installing DICOM Toolkit (May prompt for sudo password)"
    sudo -S apt-get install dcmtk
fi
######################################################################
###### Update the Database table, Config, with the user values #######
######################################################################
echo "Populating database configuration entries for the Imaging Pipeline and LORIS-MRI code and images Path:"
mysql $mysqldb -h$mysqlhost --user=$mysqluser --password="$mysqlpass" -A -e "UPDATE Config SET Value='/data/$PROJ/data/' WHERE ConfigID=(SELECT ID FROM ConfigSettings WHERE Name='dataDirBasepath')"
mysql $mysqldb -h$mysqlhost --user=$mysqluser --password="$mysqlpass" -A -e "UPDATE Config SET Value='$PROJ' WHERE ConfigID=(SELECT ID FROM ConfigSettings WHERE Name='prefix')"
mysql $mysqldb -h$mysqlhost --user=$mysqluser --password="$mysqlpass" -A -e "UPDATE Config SET Value='$email' WHERE ConfigID=(SELECT ID FROM ConfigSettings WHERE Name='mail_user')"
mysql $mysqldb -h$mysqlhost --user=$mysqluser --password="$mysqlpass" -A -e "UPDATE Config SET Value='/data/$PROJ/bin/mri/dicom-archive/get_dicom_info.pl' WHERE ConfigID=(SELECT ID FROM ConfigSettings WHERE Name='get_dicom_info')"
mysql $mysqldb -h$mysqlhost --user=$mysqluser --password="$mysqlpass" -A -e "UPDATE Config SET Value='/data/$PROJ/data/tarchive/' WHERE ConfigID=(SELECT ID FROM ConfigSettings WHERE Name='tarchiveLibraryDir')"
mysql $mysqldb -h$mysqlhost --user=$mysqluser --password="$mysqlpass" -A -e "UPDATE Config SET Value='/data/$PROJ/data/' WHERE ConfigID=(SELECT ID FROM ConfigSettings WHERE Name='imagePath') AND Value = '/data/%PROJECTNAME%/data/'"
mysql $mysqldb -h$mysqlhost --user=$mysqluser --password="$mysqlpass" -A -e "UPDATE Config SET Value='/data/$PROJ/data/' WHERE ConfigID=(SELECT ID FROM ConfigSettings WHERE Name='data') AND Value = '/data/%PROJECTNAME%/data/'"
mysql $mysqldb -h$mysqlhost --user=$mysqluser --password="$mysqlpass" -A -e "UPDATE Config SET Value='/data/$PROJ/data/' WHERE ConfigID=(SELECT ID FROM ConfigSettings WHERE Name='mincPath') AND Value = '/data/%PROJECTNAME%/data/'"
mysql $mysqldb -h$mysqlhost --user=$mysqluser --password="$mysqlpass" -A -e "UPDATE Config SET Value='/data/$PROJ/bin/mri/' WHERE ConfigID=(SELECT ID FROM ConfigSettings WHERE Name='MRICodePath') AND Value = '/data/%PROJECTNAME%/bin/mri/'"
echo
