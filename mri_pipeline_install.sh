#!/bin/bash

################################
####WHAT WILL NOT DO#############
###1)It doesn't set up the SGE
###2)It doesn't fetch the CIVET stuff   TODO:Get the CIVET stuff from somewhere and place it in h
###3)It doesn't change the config.xml

## First, check that all required modules are installed.
## Check if cpan module installed

#If MRI and TRUNK use the same user/database. Propose to specify config.xml
# to speed up the installation process
while getopts ":c:" opt; do
  case $opt in
    c)
      configFile="$OPTARG";
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
  esac
done

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

if [ ! -f "$APTGETCHECK" ]; then
    echo "\nERROR: Unable to find apt-get"
    echo "Please, ask your sysadmin to install APT-GET\n"
    exit
fi

read -p "what is the linux user which the installation will be based on? " USER
read -p "what is the project Name " PROJ   ##this will be used to create all the corresponding directories...i.e /data/gusto/bin.....


if [ ! -z "$configFile" ] && [ -f "$configFile" ]; 
then
    mysqlhost=`grep -oPm1 "(?<=<host>)[^<]+" $configFile`;
    mysqluser=`grep -oPm1 "(?<=<username>)[^<]+" $configFile`;
    mysqlpass=`grep -oPm1 "(?<=<password>)[^<]+" $configFile`;
    mysqldb=`grep -oPm1 "(?<=<database>)[^<]+" $configFile`;
    while true; do
        echo "Thoses values have been found in the config.xml?";
        echo "Hostname=> $mysqlhost";
        echo "Database=> $mysqldb";
        echo "Username=> $mysqluser";
        read -p "Would you like to keep those setting? [y,n]:" yn
        echo
        case $yn in
            [Yy]* ) break;;
            [Nn]* ) 
                    read -p "what is the database name? " mysqldb
                    read -p "What is the database host? " mysqlhost
                    read -p "What is the Mysql user? " mysqluser
                    stty -echo ##this disables the password to show up on the commandline
                    read -p "What is the mysql password? " mysqlpass;
                    echo
                    stty echo;;
            * ) echo "Please answer yes or no.";;
        esac
    done
else
    read -p "what is the database name? " mysqldb
    read -p "What is the database host? " mysqlhost
    read -p "What is the Mysql user? " mysqluser
    stty -echo ##this disables the password to show up on the commandline
    read -p "What is the mysql password? " mysqlpass; echo
    stty echo  
fi

read -p "what is your email address " email
email=${email/@/\\\\@}  ##adds a back slash before the @
echo "email is $email"


read -p "what prod file name would you like to use? default: prod? " prodfilename
if [ -z "$prodfilename" ]; then
    prodfilename="prod"
fi 
 
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
sudo -S cpan install Path::Class
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
  sudo -S su $USER -c "mkdir -p $mridir/.loris_mri"
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
echo "Create init.sh script"
##Make sure that CIVET stuff are placed at the right place
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
#echo "Changing permissions"

sudo chmod -R 750 $mridir/.loris_mri/
sudo chmod -R 750 /data/$PROJ/
sudo chmod -R 750 /data/incoming/
echo

####################################################################################
######################Add the proper Apache group user #############################
####################################################################################
sudo chgrp www-data -R /data/$PROJ/data/
sudo chgrp www-data -R /data/incoming/

echo
######################################################################################
##########################change the prod file#######################################
#####################################################################################
echo "Creating MRI config file"

cp $mridir/dicom-archive/profileTemplate $mridir/dicom-archive/.loris_mri/$prodfilename
sudo chmod 640 $mridir/dicom-archive/.loris_mri/$prodfilename

#variable  $projdir should be declared from previous pull requests addRelativeInInstallationScript
sed -e "s#project#$PROJ#g" -e "s#/PATH/TO/DATA/location#$projdir/data#g" -e "s#yourname\\\@example.com#$email#g" -e "s#/PATH/TO/get_dicom_info.pl#$mridir/dicom-archive/get_dicom_info.pl#g"  -e "s#DBNAME#$mysqldb#g" -e "s#DBUSER#$mysqluser#g" -e "s#DBPASS#$mysqlpass#g" -e "s#DBHOST#$mysqlhost#g" -e "s#/PATH/TO/dicomlib/#$projdir/data/tarchive#g" $mridir/dicom-archive/profileTemplate > $mridir/dicom-archive/.loris_mri/$prodfilename
echo "config file is located at $mridir/dicom-archive/.loris_mri/$prodfilename"
echo


######################################################################
###########Modify the config.xml########################################
######################################################################
##sed -i "s#SAME AS imagePath#/data/$PROJ/data#g" -i "s#/PATH/TO/MINC/DATA/ROOT/mri-data/minc/#data/$PROJ/data#g" $lorisdir/project/config.xml
