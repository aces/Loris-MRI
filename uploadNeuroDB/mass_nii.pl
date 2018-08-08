#!/usr/bin/perl

=pod

=head1 NAME

mass_nii.pl -- Generates NIfTI files based on the MINC files available in the
LORIS database and inserts them into the C<parameter_file> table.

=head1 SYNOPSIS

perl mass_nii.pl C<[options]>

Available options are:

-profile  : name of the config file in C<../dicom-archive/.loris_mri>

-minFileID: specifies the minimum C<FileID> to operate on

-maxFileID: specifies the maximum C<FileID> to operate on

-verbose  : be verbose

=head1 DESCRIPTION

This script generates NIfTI images for the inserted MINC files with a C<FileID>
between the specified C<minFileID> and C<maxFileID>.

=cut

use strict;
use FindBin;
use lib "$FindBin::Bin";
use Getopt::Tabular;
use NeuroDB::DBI;
use NeuroDB::File;
use NeuroDB::MRI;
use NeuroDB::ExitCodes;


## Starting the program
my $versionInfo = sprintf "%d revision %2d", q$Revision: 1.00 $
=~ /: (\d+)\.(\d+)/;


################################################################
################## Set variables for GETOPT ####################
################################################################
my $verbose    = 0;
my $profile    = undef;
my $minFileID  = undef;
my $maxFileID  = undef;
my $debug      = 0;

my $Help       = <<HELP;
******************************************************************************
MASS NIfTI CREATION SCRIPT
******************************************************************************

Author  :   Cécile Madjar based on mass_pic.pl.
                        NeuroDB lib
                        Date    :   2015/07/28
                        Version :   $versionInfo

                        This script generates NIfTI images 
                        for the inserted MINC images that 
                        are missing NIfTIs.

Documentation: perldoc mass_nii.pl

HELP

my $Usage      = <<USAGE;

Usage:    See $0 -help for more info

USAGE

my @arg_table = (
["Database options", "section"],
    ["-profile", "string", 1, \$profile, 
        "Specify the name of the config file which resides " .
        "in ../dicom-archive/.loris_mri"],

["File control", "section"],
    ["-minFileID", "integer", 1, \$minFileID, 
        "Specify the minimum FileID to operate on."], 
    ["-maxFileID", "integer", 1, \$maxFileID, 
        "Specify the maximum FileID to operate on."], 

["General options", "section"],
    ["-verbose", "boolean", 1, \$verbose, "Be verbose."]
);

GetOptions(\@arg_table, \@ARGV) ||  exit $NeuroDB::ExitCodes::GETOPT_FAILURE;


################################################################
# Checking for profile settings ################################
################################################################
if ( !$profile ) {
    print $Help;
    print STDERR "$Usage\n\tERROR: missing -profile argument\n\n";
    exit $NeuroDB::ExitCodes::PROFILE_FAILURE;
}

if (-f "$ENV{LORIS_CONFIG}/.loris_mri/$profile") {
	{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/$profile" }
}

if ( !@Settings::db ) {
    print STDERR "\n\tERROR: You don't have a \@db setting in the file "
                 . "$ENV{LORIS_CONFIG}/.loris_mri/$profile \n\n";
    exit $NeuroDB::ExitCodes::DB_SETTINGS_FAILURE;
} 



################################################################
# Establish database connection if database option is set ######
################################################################
print "Connecting to database.\n" if $verbose;
my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);


################################################################
# Query FileIDs of MINC files that don't have NIfTI associated #
################################################################

# Base of the query
my $query = <<QUERY;
SELECT 
    f.FileID 
FROM 
    files AS f 
LEFT OUTER JOIN 
    (SELECT pf.FileID, pf.Value 
     FROM parameter_file AS pf 
     JOIN parameter_type AS pt USING (ParameterTypeID) 
     WHERE pt.Name=?
    ) AS NIfTI USING (FileID) 
WHERE 
    Value IS NULL AND f.FileType=?
QUERY

# Complete query if min and max File ID have been defined.
$query .= " AND f.FileID <= ?" if defined $maxFileID;
$query .= " AND f.FileID <= ?" if defined $minFileID;

# Create array of parameters to use for query.
my @param = ('check_nii_filename', 'mnc');
push (@param, $maxFileID) if defined $maxFileID;
push (@param, $minFileID) if defined $minFileID;

# Prepare and execute query
my $sth   = $dbh->prepare($query);
$sth->execute(@param);
if ($debug) {
    print $query . "\n";
}


################################################################
# Create NIfTI files for each FileIDs from the query result ####
################################################################
my $data_dir = &NeuroDB::DBI::getConfigSetting(
                    \$dbh,'dataDirBasepath'
                    );
# Loop through FileIDs
while(my $rowhr = $sth->fetchrow_hashref()) {

    print "$rowhr->{'FileID'}\n" if $verbose;

    # Load file information
    my $file = NeuroDB::File->new(\$dbh);
    $file->loadFile($rowhr->{'FileID'});

    # Create NIfTI file
    &NeuroDB::MRI::make_nii(\$file, $data_dir);

}


################################################################
# Terminate script #############################################
################################################################

# Close database handler
$dbh->disconnect();
print "\n Finished mass_nii.pl execution\n" if $verbose;

# Exit script
exit $NeuroDB::ExitCodes::SUCCESS;


__END__

=pod

=head1 LICENSING

License: GPLv3

=head1 AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

=cut
