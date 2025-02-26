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
read -p "What is the project name? " PROJ   ##this will be used to create all the corresponding directories...i.e /data/gusto/data..... and /opt/gusto/bin
read -p "What is your email address? " email
read -p "What prod file name would you like to use? default: prod " prodfilename
if [ -z "$prodfilename" ]; then
    prodfilename="prod"
fi

# determine the mridir
installdir=`pwd`
mridir=${installdir%"/install"}

# Test the connection to the database before proceeding
echo "Testing connection to database..."

test_query_output=$(mysql -u $mysqluser -p${mysqlpass} -h $mysqlhost -D $mysqldb -e ';' 2>&1)

if [[ $? -ne 0 ]];
then
	# If the the MySQL error code was 1045, then there is an error with the username and/or password.
	# The appropriate message is then printed out. If it is a different error code, then the error message from MySQL
	# is printed out instead.
	if [[ $test_query_output == *"ERROR 1045"* ]];
	then
		echo "ERROR: invalid username and/or password. Aborting..." >&2
	else
		echo "ERROR: unable to connect to database. The MySQL error is provided below:" >&2
		echo $test_query_output >&2
		echo "Aborting..."
	fi

	exit 1
fi

echo "Successfully connected to database\n"

#################################################################################################
############################INSTALL THE PERL LIBRARIES###########################################
#################################################################################################
echo "Installing the perl libraries...This will take a few minutes..."
#echo $rootpass | sudo perl -MCPAN -e shell
#echo $rootpass | sudo -S cpan install Bundle::CPAN
sudo -S cpan App::cpanminus
sudo -S cpanm --installdeps $installdir/requirements/
sudo -S cpanm https://github.com/aces/Loris-MRI/raw/main/install/Digest-BLAKE2-0.02.tar.gz
echo

################################################################################
##Create the loris-mri python virtualenv and install the Python packages########
################################################################################
echo "Creating loris-mri Python virtualenv in $mridir/python_virtualenvs/loris-mri-python/"
# create a directory in $mridir that will store python 3 virtualenv
sudo -S su $USER -c "mkdir -m 770 -p $mridir/python_virtualenvs/loris-mri-python"
python3.11 -m venv $mridir/python_virtualenvs/loris-mri-python
source $mridir/python_virtualenvs/loris-mri-python/bin/activate
echo "Installing the Python libraries into the loris-mri virtualenv..."
pip3 install -r "$installdir/requirements/requirements.txt"
# deactivate the virtualenv for now
deactivate

#######################################################################################
#############################Create directories########################################
#######################################################################################
echo "Creating the data directories"
  sudo -S su $USER -c "mkdir -m 2770 -p /data/$PROJ/data/"
  sudo -S su $USER -c "mkdir -m 770 -p /data/$PROJ/data/trashbin"         #holds mincs that didn't match protocol
  sudo -S su $USER -c "mkdir -m 770 -p /data/$PROJ/data/tarchive"         #holds tared dicom-folder
  sudo -S su $USER -c "mkdir -m 770 -p /data/$PROJ/data/hrrtarchive"      #holds tared hrrt-folder
  sudo -S su $USER -c "mkdir -m 770 -p /data/$PROJ/data/pic"              #holds jpegs generated for the MRI-browser
  sudo -S su $USER -c "mkdir -m 770 -p /data/$PROJ/data/logs"             #holds logs from pipeline script
  sudo -S su $USER -c "mkdir -m 770 -p /data/$PROJ/data/assembly"         #holds the MINC files
  sudo -S su $USER -c "mkdir -m 770 -p /data/$PROJ/data/assembly_bids"    #holds the BIDS files derived from DICOMs
  sudo -S su $USER -c "mkdir -m 770 -p /data/$PROJ/data/batch_output"     #contains the result of the SGE (queue)
  sudo -S su $USER -c "mkdir -m 770 -p /data/$PROJ/data/bids_imports"     #contains imported BIDS studies
  sudo -S su $USER -c "mkdir -m 770 -p $mridir/dicom-archive/.loris_mri"
echo

#####################################################################################
###############incoming directory ###################################################
#####################################################################################
sudo -S su $USER -c "mkdir -m 2770 -p /data/incoming/"

# Check if the incoming directory is successfully created. If not, instructions on
# how to manually create the directory are provided.
if [ ! -d "/data/incoming/" ]
then
	echo "Error: the directory /data/incoming/ could not be created."
	echo "Please run the commands below in order to manually create the directory:"
	echo "sudo mkdir -m 2770 -p /data/incoming/"
fi

###################################################################################
#######set environment variables under .bashrc#####################################
###################################################################################
echo "Modifying environment script"
cp $installdir/templates/environment_template $mridir/environment
sed -i "s#%PROJECT%#$PROJ#g" $mridir/environment
sed -i "s#%MINC_TOOLKIT_DIR%#$MINC_TOOLKIT_DIR#g" $mridir/environment
#Make sure that CIVET stuff are placed in the right place
#source /opt/$PROJ/bin/$mridirname/environment
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
sudo chmod -R 770 /opt/$PROJ/
sudo chmod -R 770 /data/$PROJ/

# Making lorisadmin part of the apache group
sudo usermod -a -G $group $USER

#Setting group permissions for all files/dirs under /data/$PROJ/ and /opt/$PROJ/
sudo chgrp $group -R /opt/$PROJ/
sudo chgrp $group -R /data/$PROJ/

#Setting group ID for all files/dirs under /data/$PROJ/data
sudo chmod -R g+s /data/$PROJ/data/

# Setting group permissions and group ID for all files/dirs under /data/incoming
# If the directory was not created earlier, then instructions to do so manually are provided.
if [ -d "/data/incoming/" ]
then
	sudo chmod -R 770 /data/incoming/
	sudo chgrp $group -R /data/incoming/
	sudo chmod -R g+s /data/incoming/
else
	echo "After manually creating /data/incoming/, run the commands below to set the permissions:"
	echo "sudo chmod -R 770 /data/incoming/"
	echo "sudo chgrp $group -R /data/incoming"
	echo "sudo chmod -R g+s /data/incoming/"
fi

echo

#####################################################################################
##########################change the prod file#######################################
#####################################################################################
echo "Creating MRI config file"

cp $installdir/templates/profileTemplate.pl $mridir/dicom-archive/.loris_mri/$prodfilename
sudo chmod 640 $mridir/dicom-archive/.loris_mri/$prodfilename
sudo chgrp $group $mridir/dicom-archive/.loris_mri/$prodfilename

sed -e "s#DBNAME#$mysqldb#g" -e "s#DBUSER#$mysqluser#g" -e "s#DBPASS#$mysqlpass#g" -e "s#DBHOST#$mysqlhost#g" $installdir/templates/profileTemplate.pl > $mridir/dicom-archive/.loris_mri/$prodfilename
echo "config file is located at $mridir/dicom-archive/.loris_mri/$prodfilename"
echo

echo "Creating python database config file with database credentials"
cp $installdir/templates/database_config_template.py $mridir/dicom-archive/.loris_mri/database_config.py
sudo chmod 640 $mridir/dicom-archive/.loris_mri/database_config.py
sudo chgrp $group $mridir/dicom-archive/.loris_mri/database_config.py
sed -e "s#DBNAME#$mysqldb#g" -e "s#DBUSER#$mysqluser#g" -e "s#DBPASS#$mysqlpass#g" -e "s#DBHOST#$mysqlhost#g" $installdir/templates/database_config_template.py > $mridir/dicom-archive/.loris_mri/database_config.py
echo "config file for python import scripts is located at $mridir/dicom-archive/.loris_mri/database_config.py"
echo

######################################################################
###########Modify the config.xml######################################
######################################################################
#sed -i "s#SAME AS imagePath#/data/$PROJ/data#g" -i "s#/PATH/TO/MINC/DATA/ROOT/mri-data/minc/#data/$PROJ/data#g" $lorisdir/project/config.xml

################################################################################################
#####################################DICOM TOOLKIT##############################################
################################################################################################

# Detecting distribution
os_distro=$(hostnamectl |awk -F: '/Operating System:/{print $2}'|cut -f2 -d ' ')
debian=("Debian" "Ubuntu")
redhat=("Red" "CentOS" "Fedora" "Oracle")

if [[ " ${debian[*]} " =~ " $os_distro " ]]; then
	#Check if apt-get is installed
	APTGETCHECK=`which apt-get`
	if [ ! -f "$APTGETCHECK" ]; then
		echo "\nERROR: Unable to find apt-get"
		echo "Please ask your sysadmin or install apt-get\n"
		exit
	fi

	echo "Installing DICOM Toolkit (May prompt for sudo password)"
	sudo -S apt-get install dcmtk

elif [[ " ${redhat[*]} " =~ " $os_distro " ]]; then
	echo "You are running ${os_distro}. Please also see Loris-MRI Readme for notes and links to further documentation in our main GitHub Wiki on how to install the DICOM Toolkit and other required dependencies for RedHat-based distributions."
fi

######################################################################
###### Update the Database table, Config, with the user values #######
######################################################################
echo "Populating database configuration entries for the Imaging Pipeline and LORIS-MRI code and images Path:"
mysql $mysqldb -h$mysqlhost --user=$mysqluser --password="$mysqlpass" -A -e \
	"SET @email := '$email'; SET @project := '$PROJ'; SET @minc_dir := '$MINC_TOOLKIT_DIR'; SOURCE install_database.sql;"
