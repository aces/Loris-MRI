#!/bin/bash

##################################
# This script is not actively maintained. 
# and has not been supported since 15.10
##################################
echo "NOTE: Mac is no longer supported as of 15.10."
echo "This script is not actively maintained."
echo 

##################################
###WHAT THIS SCRIPT WILL NOT DO###
#1)It doesn't set up the SGE
#2)It doesn't fetch the CIVET stuff   TODO:Get the CIVET stuff from somewhere and place somewhere
#3)It doesn't change the config.xml
#4)It doesn't install DICOM toolkit


#Create a temporary log for installation and delete it on completion 
#@TODO make sure that /tmp is writable
LOGFILE="/tmp/$(basename $0).$$.tmp"
touch $LOGFILE
trap "rm  $LOGFILE" EXIT

read -p "What is the database name? " mysqldb
read -p "What is the database host? " mysqlhost
read -p "What is the MySQL user? " mysqluser
stty -echo
read -p "What is the MySQL password? " mysqlpass; echo
stty echo
read -p "What is the Linux user which the installation will be based on? " USER
read -p "What is the project name? " PROJ   ##this will be used to create all the corresponding directories...i.e /data/gusto/bin.....
read -p "What prod file name would you like to use? default: prod " prodfilename
if [ -z "$prodfilename" ]; then
    prodfilename="prod"
fi 
 
read -p "Enter the list of Site names (space separated) " site
mridir=`pwd`

#####################################################################################
#############################Create directories######################################
#####################################################################################
echo "Creating the data directories"
  sudo -S su $USER -c "mkdir -m 2770 -p /data/$PROJ/data/"
  sudo -S su $USER -c "chmod g+s /data/$PROJ/data/"
  sudo -S su $USER -c "mkdir -m 770 -p /data/$PROJ/data/trashbin"          #holds mincs that didn't match protocol
  sudo -S su $USER -c "mkdir -m 770 -p /data/$PROJ/data/tarchive"          #holds tared dicom-folder
  sudo -S su $USER -c "mkdir -m 770 -p /data/$PROJ/data/pic"               #holds jpegs generated for the MRI-browser
  sudo -S su $USER -c "mkdir -m 770 -p /data/$PROJ/data/logs"              #holds logs from pipeline script
  sudo -S su $USER -c "mkdir -m 770 -p /data/$PROJ/data/assembly"          #holds the MINC files
  sudo -S su $USER -c "mkdir -m 770 -p /data/$PROJ/data/batch_output"      #contains the result of the SGE (queue)
  sudo -S su $USER -c "mkdir -m 770 -p /data/$PROJ/data/bids_imports"      #contains imported BIDS studies
  sudo -S su $USER -c "mkdir -m 770 -p $mridir/dicom-archive/.loris_mri"
echo
#####################################################################################
###############incoming directory ###################################################
#####################################################################################
sudo -S su $USER -c "mkdir -m 2770 -p /data/incoming/";

###################################################################################
#######set environment variables under .bashrc#####################################
###################################################################################
echo "Modifying environment script"
sed -i "s#%PROJECT%#$PROJ#g" $mridir/environment
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

sudo chmod -R 770 $mridir/.loris_mri/
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