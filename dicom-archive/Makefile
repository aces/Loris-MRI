SHELL=/bin/sh

CVS_HEAD=" $Id: Makefile 3 2007-12-11 20:10:36Z jharlap $ "

tar        = dicomTar
summary    = dicomSummary
info       = get_dicom_info
distfolder = dcmTools

version:
	#     +-------------------------------------+
	#     |  DicomTar PAR package builder       |
	#     +-------------------------------------+
	@echo
	@echo "Syntax: make [option]"
	@echo
	@echo "all	- (cvsup) dist"
	@echo "cvsup	- check cvs for newer versions of the above before doing anything"
	@echo "dist	- update cvs par and create binaries"
	@echo

# default
all:
	make dist 

# check for updates first
cvsup:
	cvs up Makefile dcm_archive_table.sql dicomSummary.pl dicomTar.pl get_dicom_info.pl

# make the binaries
dist:	
	mkdir $(distfolder)
	pp -F Bleach -f Bleach -B -o $(distfolder)/$(tar) $(tar).pl
	pp -F Bleach -f Bleach -B -o $(distfolder)/$(summary) $(summary).pl
	pp -F Bleach -f Bleach -B -o $(distfolder)/$(info) $(info).pl

# remove the last build
clean:
	rm -rf $(distfolder)
