SHELL=/bin/sh
CVS_HEAD=" $Id: Makefile,v 1.3 2006/10/17 16:07:28 moi Exp $ "

version:
	#     +-------------------------------------+
	#     |      Uploader package builder       |
	#     +-------------------------------------+
	@echo
	@echo "Syntax: make [option]"
	@echo
	@echo "cvsup	- check cvs for newer versions of the above before doing anything"
	@echo "dist	- create standalone binary"
	@echo

cvsup:
	cvs up 

dist:	
	pp -X FileHandle -F Bleach -f Bleach -a /usr/lib/libmysqlclient.a -B -o uploader upload


# scp to public target

public: 
	scp uploader $(publicTarget)
