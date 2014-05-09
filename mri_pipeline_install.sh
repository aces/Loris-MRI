#!/bin/bash

################################
####WHAT WILL NOT DO#############
###1)It doesn't set up the SGE
###2)It doesn't fetch the CIVET stuff   TODO:Get the CIVET stuff from somewhere and place it in h
###3)It doesn't change the config.xml

## First, check that all required modules are installed.
## Check if cpan module installed

#TODO: Mathieu Failed to find minc-tools or dcmtk send a warning message 
#TODO: Mathieu Source minc-toolkit-config.sh into environnement file
#TODO: We should add an option for populating mysql parameter from Loris-Trunk config.xml file
#      And test mysql config at the same time 
#TODO: mail seem boggus in prod file


if [ ! -f "$(basename $0)" ];
then
   echo "You must be in Loris-MRI trunk directory to launch installation script."
   echo
   exit
fi
 
#make sure that dicom-archive trunk project is available
if [ ! -f "dicom-archive/profileTemplate" ];
then
   echo "Could not find dicom-archive trunk, do the intall prior to run this script."
   echo
   exit
fi

#Create a temporary log for installation and delete it on completion 
#@TODO make sure that /tmp is writable
LOGFILE="/tmp/$(basename $0).$$.tmp"
touch $LOGFILE
trap "rm  $LOGFILE" EXIT

CPANCHECK=`which cpan`
if [ ! -f "$CPANCHECK" ]; 
then
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
if which apt-get > $LOGFILE 2>&1;
then
    PACKAGEMANAGER=APTGET
elif which zypper > $LOGFILE 2>&1;
then
    PACKAGEMANAGER=ZYPPER
else
    echo "\nERROR: Unable to find the package manager"
    echo "Please, ask your sysadmin to install apt-get or zypper\n"
fi

read -p "what is the project Name?" PROJ   ##this will be used to create all the corresponding directories...i.e /data/gusto/bin.....
read -p "Please specify the directory where the project should be install or press ENTER, default: /data/? " rootdir
if [ -z "$rootdir" ]; then
    rootdir="/data/"
fi

#make sure that root directory exists
if [ ! -d "$rootdir" ];
then
   echo "ERROR: root directory $rootdir do not exists."
   echo
   exit
fi

#clean up extra slash
rootdir=$(readlink -m $rootdir) 
projdir=$(readlink -m $rootdir/$PROJ)

read -p "what is the linux user which the installation will be based on, default: $USER? " username
if [ -z "$username" ]; 
then
    username=$USER
fi 

while true; do
    read -p "I will attempt to create folder $projdir, is that what you want? [y,n]:" yn
    case $yn in
        [Yy]* ) sudo -S mkdir -p $projdir; 
                sudo chown $username $projdir; 
                break;;
        [Nn]* ) exit;;
        * ) echo "Please answer yes or no.";;
    esac
done

mridir=`pwd`

read -p "what is the database name? " mysqldb
read -p "What is the database host? " mysqlhost
read -p "What is the Mysql user? " mysqluser
stty -echo ##this disables the password to show up on the commandline
read -p "What is the mysql password? " mysqlpass; echo
stty echo


read -p "what is your email address " email
email=${email/@/\\\\@}  ##adds a back slash before the @
echo "email is $email"
read -p "what is the prod file name default: prod? " prodfilename
if [ -z "$prodfilename" ]; then
    prodfilename="prod"
fi 

read -p "Enter the list of Site names (space separated) " site

##read -p "Enter Full Loris-code directory path "   lorisdir

#################################################################################################
########################################MINC TOOL###############################################
##################################################################################################

if [ "$PACKAGEMANAGER" == "APTGET" ];
then
    echo "installing Minc toolkit (May prompt for sudo password)"
    sudo -S apt-get install minc-tools
    echo
else
    echo "\nWARNING: Unable to determine if minc-tools are installed"
    echo "Please, check your proper installation\n"
fi

if [ "$PACKAGEMANAGER" == "APTGET" ];
then
    echo "installing dicom toolkit (May prompt for sudo password)"
    sudo -S apt-get install dcmtk
    echo
elif [ "$PACKAGEMANAGER" == "ZYPPER" ];
then
    echo "installing dicom toolkit (May prompt for sudo password)"
    sudo -S zypper --non-interactive install dcmtk
    echo    
else
    echo "\nWARNING: Unable to determine if dcmtk are installed"
    echo "Please, check your proper installation\n" 
    echo
fi

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

sudo -S su $username -c "mkdir -p $projdir/data/"
sudo -S su $username -c "mkdir -p $projdir/data/trashbin"   ##holds mincs that didn't match protocol
sudo -S su $username -c "mkdir -p $projdir/data/tarchive"   ##holds tared dicom-folder
sudo -S su $username -c "mkdir -p $projdir/data/pic"           ##holds jpegs generated for the MRI-browser
sudo -S su $username -c "mkdir -p $projdir/data/logs"         ## holds logs from pipeline script
sudo -S su $username -c "mkdir -p $projdir/data/jiv"            ## holds JIVs used for JIV viewer
sudo -S su $username -c "mkdir -p $projdir/data/assembly" ## holds the MINC files
sudo -S su $username -c "mkdir -p $projdir/data/batch_output"  ##contains the result of the SGE (queue

#create .loris_mri directory only if it do not exists
if [ ! -d "$mridir/dicom-archive/.loris_mri" ];
then
    sudo -S su $username -c "mkdir -p $mridir/dicom-archive/.loris_mri"
else
   echo "Warning: directory .loris_mri already exists, Skipping creation."
   echo
fi
  
echo
#######################################################################################
###############incoming directory using sites########################################
#######################################################################################
echo "Creating incoming director(y/ies)"

if [ ! -d "$rootdir/incoming" ];
then
    sudo -S su $username -c "mkdir -p $rootdir/incoming/"
fi

echo "Creating incoming director(y/ies) for each Site(s)"
for s in $site; do 
    sudo -S su $username -c "mkdir -p $rootdir/incoming/$s/incoming";
done;
echo

####################################################################################
#######set environment variables under .bashrc#####################################
###################################################################################

echo "Create initialisation environment script"

#sed -i "s#%PROJECT%#$PROJ#g" $mridir/environment
##Make sure that CIVET stuff are placed in the right place
##source  /data/$PROJ/bin/$mridirname/environment

TEXT="export LORIS_MRI_HOME=$mridir"
TEXT="$TEXT\nexport PATH=\$LORIS_MRI_HOME:\$LORIS_MRI_HOME/uploadNeuroDB:\$LORIS_MRI_HOME/dicom-archive:\$PATH "
TEXT="$TEXT\nexport PERL5LIB=\$LORIS_MRI_HOME/uploadNeuroDB:\$PERL5LIB "
TEXT="$TEXT\nexport LORIS_CONFIG=\$LORIS_MRI_HOME/dicom-archive "
TEXT="$TEXT\nexport TMPDIR=/tmp"
echo -e $TEXT > init.sh
echo
 
####################################################################################
######################change permissions ##########################################
####################################################################################
echo "Changing permissions"
#TODO: arguing about the recusivity of those functions 

#Checking if .loris_mri directory have permission 750
if [ $(find $mridir/dicom-archive/.loris_mri -maxdepth 0 -type d -perm 750  | wc -l) -eq 0 ]; 
then
    echo "Warning, wrong permission for .loris_mri, fixing it!"
    echo
    sudo chmod -R 750 $mridir/dicom-archive/.loris_mri/
fi

if [ $(find $projdir -maxdepth 0 -type d -perm 750  | wc -l) -eq 0 ]; 
then
    echo "Warning, wrong permission for $projdir, fixing it!"
    echo
    sudo chmod -R 750 $projdir
fi

if [ $(find $rootdir/incoming -maxdepth 0 -type d -perm 750  | wc -l) -eq 0 ]; 
then
    echo "Warning, wrong permission for $rootdir/incoming, fixing it!"
    echo
    sudo chmod -R 750 $rootdir/incoming
fi

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

sudo chgrp $group -R $projdir/data/
sudo chgrp $group -R $rootdir/incoming/

echo
######################################################################################
##########################change the prod file#######################################
#####################################################################################
echo "Creating MRI config file"

cp $mridir/dicom-archive/profileTemplate $mridir/dicom-archive/.loris_mri/$prodfilename

sudo chmod 640 $mridir/dicom-archive/.loris_mri/$prodfilename

sed -e "s#project#$PROJ#g" -e "s#/PATH/TO/DATA/location#$projdir/data#g" -e "s#yourname\\\@example.com#$email#g" -e "s#/PATH/TO/get_dicom_info.pl#$mridir/dicom-archive/get_dicom_info.pl#g"  -e "s#DBNAME#$mysqldb#g" -e "s#DBUSER#$mysqluser#g" -e "s#DBPASS#$mysqlpass#g" -e "s#DBHOST#$mysqlhost#g" -e "s#/PATH/TO/dicomlib/#$projdir/data/tarchive#g" $mridir/dicom-archive/profileTemplate > $mridir/dicom-archive/.loris_mri/$prodfilename
echo "config file is located at $mridir/dicom-archive/.loris_mri/$prodfilename"
echo

######################################################################
###########Modify the config.xml########################################
######################################################################
##sed -i "s#SAME AS imagePath#/data/$PROJ/data#g" -i "s#/PATH/TO/MINC/DATA/ROOT/mri-data/minc/#data/$PROJ/data#g" $lorisdir/project/config.xml

echo "PLEASE add to your .profile or .bashrc file# source $mridir/init.sh "
echo "and do not forget to specify minc-toolkit binaries directory in your \$PATH environnement variables"
echo "You may add this line#  source /PATH/TO/MINC/minc-toolkit-config.sh in your init.sh file "
echo
