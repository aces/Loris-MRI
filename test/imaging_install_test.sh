#!/bin/bash

mysqldb=$1
mysqlhost="db"
mysqluser=$2
mysqlpass=$3
USER="root"
PROJ="loris"
prodfilename="prod"

mridir="/opt/loris/bin/mri"

minc_config=/opt/minc/1.9.18/minc-toolkit-config.sh
if [ -f "$minc_config" ]; then
  MINC_TOOLKIT_DIR=/opt/minc/1.9.18
else
  MINC_TOOLKIT_DIR=""
fi

#######################################################################################
#############################Create directories########################################
#######################################################################################
echo "Creating the data directories"
  mkdir -m 2770 -p /data/$PROJ/
  mkdir -m 770 -p /data/$PROJ/trashbin         #holds mincs that didn't match protocol
  mkdir -m 770 -p /data/$PROJ/tarchive         #holds tared dicom-folder
  mkdir -m 770 -p /data/$PROJ/chunks           #holds electrophysiology chunks folder
  mkdir -m 770 -p /data/$PROJ/hrrtarchive      #holds tared hrrt-folder
  mkdir -m 770 -p /data/$PROJ/pic              #holds jpegs generated for the MRI-browser
  mkdir -m 770 -p /data/$PROJ/logs             #holds logs from pipeline script
  mkdir -m 770 -p /data/$PROJ/assembly         #holds the MINC files
  mkdir -m 770 -p /data/$PROJ/assembly_bids    #holds the BIDS files derived from DICOMs
  mkdir -m 770 -p /data/$PROJ/batch_output     #contains the result of the SGE (queue)
  mkdir -m 770 -p /data/$PROJ/bids_imports     #contains imported BIDS studies
  mkdir -m 770 -p $mridir/config
echo

#####################################################################################
###############incoming directory ###################################################
#####################################################################################
mkdir -m 2770 -p /data/incoming/

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
cp $mridir/install/templates/environment_template $mridir/environment
sed -i "s#%PROJECT%#$PROJ#g" $mridir/environment
sed -i "s#%MINC_TOOLKIT_DIR%#$MINC_TOOLKIT_DIR#g" $mridir/environment
#Make sure that CIVET stuff are placed in the right place
#source /opt/$PROJ/bin/$mridirname/environment
export TMPDIR=/tmp
echo

####################################################################################
######################Add the proper Apache group user #############################
####################################################################################
group=root

####################################################################################
######################change permissions ###########################################
####################################################################################
#echo "Changing permissions"
chmod -R 770 /opt/$PROJ/
chmod -R 770 /data/$PROJ/

#Setting group permissions for all files/dirs under /data/$PROJ/ and /opt/$PROJ/
chgrp $group -R /opt/$PROJ/
chgrp $group -R /data/$PROJ/

#Setting group ID for all files/dirs under /data/$PROJ/
chmod -R g+s /data/$PROJ/

# Setting group permissions and group ID for all files/dirs under /data/incoming
# If the directory was not created earlier, then instructions to do so manually are provided.
if [ -d "/data/incoming/" ]
then
	chmod -R 770 /data/incoming/
	chgrp $group -R /data/incoming/
	chmod -R g+s /data/incoming/
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

cp $mridir/install/templates/profileTemplate.pl $mridir/config/$prodfilename
chmod 640 $mridir/config/$prodfilename
chgrp $group $mridir/config/$prodfilename

sed -e "s#DBNAME#$mysqldb#g" -e "s#DBUSER#$mysqluser#g" -e "s#DBPASS#$mysqlpass#g" -e "s#DBHOST#$mysqlhost#g" $mridir/install/templates/profileTemplate.pl > $mridir/config/$prodfilename
echo "config file is located at $mridir/config/$prodfilename"
echo

echo "Creating python database config file with database credentials"
cp $mridir/install/templates/config_template.py $mridir/config/config.py
chmod 640 $mridir/config/config.py
chgrp $group $mridir/config/config.py
sed -e "s#DBNAME#$mysqldb#g" -e "s#DBUSER#$mysqluser#g" -e "s#DBPASS#$mysqlpass#g" -e "s#DBHOST#$mysqlhost#g" $mridir/install/templates/config_template.py > $mridir/config/config.py
echo "config file for python import scripts is located at $mridir/config/config.py"
