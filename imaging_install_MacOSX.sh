#!/bin/bash

##################################
###WHAT THIS SCRIPT WILL NOT DO###
#1)It doesn't set up the SGE
#2)It doesn't fetch the CIVET stuff   TODO:Get the CIVET stuff from somewhere and place somewhere
#3)It doesn't change the config.xml


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

read -p "What is your email address? " email

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
  sudo -S su $USER -c "mkdir -p /data/$PROJ/data/"
  sudo -S su $USER -c "mkdir -p /data/$PROJ/data/trashbin"          #holds mincs that didn't match protocol
  sudo -S su $USER -c "mkdir -p /data/$PROJ/data/tarchive"          #holds tared dicom-folder
  sudo -S su $USER -c "mkdir -p /data/$PROJ/data/pic"               #holds jpegs generated for the MRI-browser
  sudo -S su $USER -c "mkdir -p /data/$PROJ/data/logs"              #holds logs from pipeline script
  sudo -S su $USER -c "mkdir -p /data/$PROJ/data/jiv"               #holds JIVs used for JIV viewer
  sudo -S su $USER -c "mkdir -p /data/$PROJ/data/assembly"          #holds the MINC files
  sudo -S su $USER -c "mkdir -p /data/$PROJ/data/batch_output"      #contains the result of the SGE (queue
  sudo -S su $USER -c "mkdir -p $mridir/dicom-archive/.loris_mri"
echo
#####################################################################################
###############incoming directory using sites########################################
#####################################################################################
sudo -S su $USER -c "mkdir -p /data/incoming/";
echo "Creating incoming director(y/ies)"
 for s in $site; do 
  sudo -S su $USER -c "mkdir -p /data/incoming/$s/incoming";
 done;
echo

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
######################change permissions ###########################################
####################################################################################
#echo "Changing permissions"

sudo chmod -R 750 $mridir/.loris_mri/
sudo chmod -R 750 /data/$PROJ/
sudo chmod -R 750 /data/incoming/
echo

#####################################################################################
##########################change the prod file#######################################
#####################################################################################
echo "Creating MRI config file"

cp $mridir/dicom-archive/profileTemplate $mridir/dicom-archive/.loris_mri/$prodfilename
sudo chmod 640 $mridir/dicom-archive/.loris_mri/$prodfilename

sed -e "s#project#$PROJ#g" -e "s#/PATH/TO/DATA/location#/data/$PROJ/data#g" -e "s#yourname\@example.com#$email#g" -e "s#/PATH/TO/get_dicom_info.pl#$mridir/dicom-archive/get_dicom_info.pl#g"  -e "s#DBNAME#$mysqldb#g" -e "s#DBUSER#$mysqluser#g" -e "s#DBPASS#$mysqlpass#g" -e "s#DBHOST#$mysqlhost#g" -e "s#/PATH/TO/dicomlib/#/data/$PROJ/data/tarchive#g" $mridir/dicom-archive/profileTemplate > $mridir/dicom-archive/.loris_mri/$prodfilename
echo "config file is located at $mridir/dicom-archive/.loris_mri/$prodfilename"
echo

