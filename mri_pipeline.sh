#!/bin/bash

################################
####WHAT WILL NOT DO#############
###1)It doesn't set up the SGE
###2)It doesn't fetch the CIVET stuff   TODO:Get the CIVET stuff from somewhere and place it in h
###3)It doesn't change the config.xml

## First, check that all required modules are installed.
## Check if cpan module installed
CPANCHECK=`which cpan`
if [ ! -f "$CPANCHECK" ]; then
    echo "\nERROR: Unable to find cpan"
    echo "Please, ask your sysadmin to install CPAN\n"
    exit
fi
## Check if make is installed
MAKECHECK=`which make`
if [ ! -f "$MAKECHECK" ]; then
    echo "\nERROR: Unable to find make"
    echo "Please, ask your sysadmin to install MAKE\n"
    exit
fi
## Check if apt-get is install
APTGETCHECK=`which apt-get`
if [ ! -f "$APTGETCHECK" ]; then
    echo "\nERROR: Unable to find apt-get"
    echo "Please, ask your sysadmin to install APT-GET\n"
    exit
fi


read -p "what is the database name? " mysqldb
read -p "What is the database host? " mysqlhost
read -p "What is the Mysql user? " mysqluser
stty -echo ##this disables the password to show up on the commandline
read -p "What is the mysql password? " mysqlpass; echo
stty echo

read -p "what is the linux user which the installation will be based on? " USER
read -p "what is the project Name " PROJ   ##this will be used to create all the corresponding directories...i.e /data/gusto/bin.....

read -p "what is your email address " email
email=${email/@/\\\\@}  ##adds a back slash before the @
echo "email is $email" 
read -p "Enter the list of Site names (space separated) " site
mridir=`pwd`
##read -p "Enter Full Loris-code directory path "   lorisdir

#################################################################################################
########################################MINC TOOL###############################################
##################################################################################################
echo "installing Minc toolkit (May prompt for sudo password)"
sudo -S apt-get install minc-tools
echo

echo "installing dicom toolkit (May prompt for sudo password)"
sudo -S apt-get install dcmtk
echo
#################################################################################################
############################INSTALL THE PERL LIBRARIES############################################
#################################################################################################
echo "Installing the perl libraries...THis will take a few minutes..."
##echo $rootpass | sudo perl -MCPAN -e shell
sudo -S cpan install Math::Round
##echo $rootpass | sudo -S cpan install Bundle::CPAN
sudo -S cpan install Getopt::Tabular
sudo -S cpan install Time::JulianDay
echo
##########################################################################################
#############################Create directories########################################
#########################################################################################
 echo "Creating the data directories"
  sudo -S su $USER -c "mkdir -p /data/$PROJ/data/"
  sudo -S su $USER -c "mkdir -p /data/$PROJ/data/trashbin"   ##holds mincs that didn't match protocol
  sudo -S su $USER -c "mkdir -p /data/$PROJ/data/tarchive"   ##holds tared dicom-folder
  sudo -S su $USER -c "mkdir -p /data/$PROJ/data/pic"           ##holds jpegs generated for the MRI-browser
  sudo -S su $USER -c "mkdir -p /data/$PROJ/data/logs"         ## holds logs from pipeline script
  sudo -S su $USER -c "mkdir -p /data/$PROJ/data/jiv"            ## holds JIVs used for JIV viewer
  sudo -S su $USER -c "mkdir -p /data/$PROJ/data/assembly" ## holds the MINC files
  sudo -S su $USER -c "mkdir -p /data/$PROJ/data/batch_output"  ##contains the result of the SGE (queue
  sudo -S su $USER -c "mkdir -p $mridir/.neurodb"
echo
#######################################################################################
 ###############incoming directory using sites########################################
#######################################################################################
 echo "Creating incoming director(y/ies)"
  for s in $site; do 
   sudo -S su $USER -c "mkdir -p /data/incoming/$s/incoming";
  done;
 echo

####################################################################################
#######set environment variables under .bashrc#####################################
###################################################################################
echo "Modifying environment script"
sed -i "s#PROJECT#$PROJ#g" $mridir/environment
##Make sure that CIVET stuff are placed in the right place
##source  /data/$PROJ/bin/$mridirname/environment
export TMPDIR=/tmp
echo

####################################################################################
######################change permissions ##########################################
####################################################################################
#echo "Changing permissions"

sudo chmod -R 750 $mridir/.neurodb/
sudo chmod -R 750 /data/$PROJ/
sudo chmod -R 750 /data/incoming/

echo
######################################################################################
##########################change the prod file#######################################
#####################################################################################
echo "Creating MRI config file"

cp $mridir/dicom-archive/profileTemplate $mridir/.neurodb/prod
sudo chmod 640 $mridir/.neurodb/prod
sed -e "s#project#$PROJ#g" -e "s#/PATH/TO/DATA/location#/data/$PROJ/data#g" -e "s#yourname\\\@gmail.com#$email#g" -e "s#/PATH/TO/get_dicom_info.pl#$mridir/dicom-archive/get_dicom_info.pl#g"  -e "s#DBNAME#$mysqldb#g" -e "s#DBUSER#$mysqluser#g" -e "s#DBPASS#$mysqlpass#g" -e "s#DBHOST#$mysqlhost#g" -e "s#/PATH/TO/dicomlib/#/data/$PROJ/data/tarchive#g" $mridir/dicom-archive/profileTemplate > $mridir/.neurodb/prod
echo

######################################################################
###########Modify the config.xml########################################
######################################################################
##sed -i "s#SAME AS imagePath#/data/$PROJ/data#g" -i "s#/PATH/TO/MINC/DATA/ROOT/mri-data/minc/#data/$PROJ/data#g" $lorisdir/project/config.xml
