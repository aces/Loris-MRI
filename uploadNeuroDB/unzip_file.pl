#! /usr/bin/perl
use strict;
use warnings;
use Carp;
use Getopt::Tabular;
use FileHandle;
use File::Basename;
use File::Temp qw/ tempdir /;
use Data::Dumper;
use FindBin;
use Cwd qw/ abs_path /;
################################################################
# These are the NeuroDB modules to be used #####################
################################################################
use lib "$FindBin::Bin";
use NeuroDB::FileDecompress;
################################################################
my $file_decompress = NeuroDB::FileDecompress->new(
			'/home/lorisadmin/Desktop/A1470_316392_3month_zia.tgz'
                       
                     );

my $result =  $file_decompress->Extract(
		'/home/lorisadmin/Desktop/decompress_folder'
	      );


