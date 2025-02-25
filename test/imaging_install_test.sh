#!/bin/bash

mysqldb=$1
mysqlhost="db"
mysqluser=$2
mysqlpass=$3
USER="root"
PROJ="loris"
prodfilename="prod"

mridir="/opt/loris/bin/mri"

#######################################################################################
#############################Create directories########################################
#######################################################################################
echo "Creating the data directories"
  sudo -S su $USER -c "mkdir -m 2770 -p /data/$PROJ/"
  sudo -S su $USER -c "mkdir -m 770 -p /data/$PROJ/trashbin"         #holds mincs that didn't match protocol
  sudo -S su $USER -c "mkdir -m 770 -p /data/$PROJ/tarchive"         #holds tared dicom-folder
  sudo -S su $USER -c "mkdir -m 770 -p /data/$PROJ/hrrtarchive"      #holds tared hrrt-folder
  sudo -S su $USER -c "mkdir -m 770 -p /data/$PROJ/pic"              #holds jpegs generated for the MRI-browser
  sudo -S su $USER -c "mkdir -m 770 -p /data/$PROJ/logs"             #holds logs from pipeline script
  sudo -S su $USER -c "mkdir -m 770 -p /data/$PROJ/assembly"         #holds the MINC files
  sudo -S su $USER -c "mkdir -m 770 -p /data/$PROJ/assembly_bids"    #holds the BIDS files derived from DICOMs
  sudo -S su $USER -c "mkdir -m 770 -p /data/$PROJ/batch_output"     #contains the result of the SGE (queue)
  sudo -S su $USER -c "mkdir -m 770 -p /data/$PROJ/bids_imports"     #contains imported BIDS studies
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
cp $mridir/install/environment $mridir/environment
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
sudo chmod -R 770 /opt/$PROJ/
sudo chmod -R 770 /data/$PROJ/

# Making lorisadmin part of the apache group
sudo usermod -a -G $group $USER

#Setting group permissions for all files/dirs under /data/$PROJ/ and /opt/$PROJ/
sudo chgrp $group -R /opt/$PROJ/
sudo chgrp $group -R /data/$PROJ/

#Setting group ID for all files/dirs under /data/$PROJ/
sudo chmod -R g+s /data/$PROJ/

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

cp $mridir/install/profileTemplate.pl $mridir/dicom-archive/.loris_mri/$prodfilename
sudo chmod 640 $mridir/dicom-archive/.loris_mri/$prodfilename
sudo chgrp $group $mridir/dicom-archive/.loris_mri/$prodfilename

sed -e "s#DBNAME#$mysqldb#g" -e "s#DBUSER#$mysqluser#g" -e "s#DBPASS#$mysqlpass#g" -e "s#DBHOST#$mysqlhost#g" $mridir/install/profileTemplate.pl > $mridir/dicom-archive/.loris_mri/$prodfilename
echo "config file is located at $mridir/dicom-archive/.loris_mri/$prodfilename"
echo

echo "Creating python database config file with database credentials"
cp $mridir/install/database_config_template.py $mridir/dicom-archive/.loris_mri/database_config.py
sudo chmod 640 $mridir/dicom-archive/.loris_mri/database_config.py
sudo chgrp $group $mridir/dicom-archive/.loris_mri/database_config.py
sed -e "s#DBNAME#$mysqldb#g" -e "s#DBUSER#$mysqluser#g" -e "s#DBPASS#$mysqlpass#g" -e "s#DBHOST#$mysqlhost#g" $mridir/install/database_config_template.py > $mridir/dicom-archive/.loris_mri/database_config.py
echo "config file for python import scripts is located at $mridir/dicom-archive/.loris_mri/database_config.py"
