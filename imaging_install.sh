#!/bin/bash

##################################
###WHAT THIS SCRIPT WILL NOT DO###
#1)It doesn't set up the SGE
#2)It doesn't fetch the CIVET stuff   TODO:Get the CIVET stuff from somewhere and place it in somewhere
#3)It doesn't change the config.xml
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
#Check if apt-get is install
APTGETCHECK=`which apt-get`
if [ ! -f "$APTGETCHECK" ]; then
    echo "\nERROR: Unable to find apt-get"
    echo "Please ask your sysadmin or install apt-get\n"
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

################################################################################################
#####################################DICOM TOOLKIT##############################################
################################################################################################
echo "Installing dicom toolkit (May prompt for sudo password)"
sudo -S apt-get install dcmtk
echo

#################################################################################################
############################INSTALL THE PERL LIBRARIES###########################################
#################################################################################################
echo "Installing the perl libraries...THis will take a few minutes..."
#echo $rootpass | sudo perl -MCPAN -e shell
sudo -S cpan install Math::Round
#echo $rootpass | sudo -S cpan install Bundle::CPAN
sudo -S cpan install Getopt::Tabular
sudo -S cpan install Time::JulianDay
sudo -S cpan install Path::Class
sudo -S cpan install Archive::Extract
sudo -S cpan install Archive::Zip
echo

#######################################################################################
#############################Create directories########################################
#######################################################################################
echo "Creating the data directories"
  sudo -S su $USER -c "mkdir -m 2770 -p /data/$PROJ/data/"
  sudo -S su $USER -c "mkdir -m 770 -p /data/$PROJ/data/trashbin"         #holds mincs that didn't match protocol
  sudo -S su $USER -c "mkdir -m 770 -p /data/$PROJ/data/tarchive"         #holds tared dicom-folder
  sudo -S su $USER -c "mkdir -m 770 -p /data/$PROJ/data/pic"              #holds jpegs generated for the MRI-browser
  sudo -S su $USER -c "mkdir -m 770 -p /data/$PROJ/data/logs"             #holds logs from pipeline script
  sudo -S su $USER -c "mkdir -m 770 -p /data/$PROJ/data/jiv"              #holds JIVs used for JIV viewer
  sudo -S su $USER -c "mkdir -m 770 -p /data/$PROJ/data/assembly"         #holds the MINC files
  sudo -S su $USER -c "mkdir -m 770 -p /data/$PROJ/data/batch_output"     #contains the result of the SGE (queue
  sudo -S su $USER -c "mkdir -m 770 -p $mridir/dicom-archive/.loris_mri"
echo

#####################################################################################
###############incoming directory using sites########################################
#####################################################################################
sudo -S su $USER -c "mkdir -m 2770 -p /data/incoming/"
echo "Creating incoming director(y/ies)"
 for s in $site; do 
  sudo -S su $USER -c "mkdir -m 770 -p /data/incoming/$s/incoming"
 done
echo

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

sed -e "s#project#$PROJ#g" -e "s#/PATH/TO/DATA/location#/data/$PROJ/data#g" -e "s#/PATH/TO/BIN/location#$mridir#g" -e "s#yourname\\\@example.com#$email#g" -e "s#/PATH/TO/get_dicom_info.pl#$mridir/dicom-archive/get_dicom_info.pl#g"  -e "s#DBNAME#$mysqldb#g" -e "s#DBUSER#$mysqluser#g" -e "s#DBPASS#$mysqlpass#g" -e "s#DBHOST#$mysqlhost#g" -e "s#/PATH/TO/dicomlib/#/data/$PROJ/data/tarchive#g" $mridir/dicom-archive/profileTemplate > $mridir/dicom-archive/.loris_mri/$prodfilename
echo "config file is located at $mridir/dicom-archive/.loris_mri/$prodfilename"
echo

######################################################################
###########Modify the config.xml######################################
######################################################################
#sed -i "s#SAME AS imagePath#/data/$PROJ/data#g" -i "s#/PATH/TO/MINC/DATA/ROOT/mri-data/minc/#data/$PROJ/data#g" $lorisdir/project/config.xml
