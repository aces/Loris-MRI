#!/usr/bin/perl

=pod

=head1 NAME

mass_pic.pl -- Generates check pic for the LORIS database system


=head1 SYNOPSIS

perl mass_pic.pl C<[options]>

Available options are:

-profile   : name of the config file in ../dicom-archive/.loris_mri

-mincFileID: integer, minimum FileID to operate on

-maxFileID : integer, maximum FileID to operate on

-verbose   : be verbose


=head1 DESCRIPTION

This scripts will generate check pics for every registered MINC file that
have a C<FileID> from the C<files> table between the specified C<minFileID>
and C<maxFileID>.

=cut


use strict;
use FindBin;
use lib "$FindBin::Bin";
use Getopt::Tabular;
use NeuroDB::DBI;
use NeuroDB::File;
use NeuroDB::MRI;
################################################################
################## Set stuff for GETOPT ########################
################################################################
my $verbose    = 0;
my $profile    = undef;
my $minFileID  = undef;
my $maxFileID  = undef;
my $query;
my $debug       = 0;
my $Usage = "mass_pic.pl generates check pic images for NeuroDB for those ".
            "files that are missing pics. ".
            " \n\n See $0 -help for more info\n\n".
            "Documentation: perldoc mass_pic.pl\n\n";

my @arg_table =
    (
         ["Database options", "section"],
         ["-profile","string",1, \$profile, "Specify the name of the ".   
          "config file which resides in ../dicom-archive/.loris_mri"],
         ["File control", "section"],
         ["-minFileID", "integer", 1, \$minFileID, 
          "Specify the minimum FileID to operate on."], 
         ["-maxFileID", "integer", 1, \$maxFileID, 
          "Specify the maximum FileID to operate on."], 
         ["General options", "section"],
         ["-verbose", "boolean", 1,   \$verbose, "Be verbose."],
    );

GetOptions(\@arg_table, \@ARGV) ||  exit 1;

################################################################
################ checking for profile settings #################
################################################################
if (-f "$ENV{LORIS_CONFIG}/.loris_mri/$profile") {
	{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/$profile" }
}
if ($profile && !@Settings::db) {
    print "\n\tERROR: You don't have a configuration file named '$profile' ". 
          "in:  $ENV{LORIS_CONFIG}/.loris_mri/ \n\n"; 
    exit 33;
} 

if (!$profile) { 
    print $Usage; 
    print "\n\tERROR: You must specify an existing profile.\n\n";  
    exit 33;  
}

################################################################
# Establish database connection if database option is set ######
################################################################
print "Connecting to database.\n" if $verbose;
my $dbh = &NeuroDB::DBI::connect_to_db(@Settings::db);

################################################################
# Where the pics should go #####################################
################################################################
my $data_dir = &NeuroDB::DBI::getConfigSetting(
                    \$dbh,'dataDirBasepath'
                    );
my $pic_dir = $data_dir . '/pic';

################################################################
##### Now go make the pics #####################################
################################################################
$query = "SELECT \@checkPicID:=ParameterTypeID FROM parameter_type WHERE ".
          "Name='check_pic_filename'";
$dbh->do($query);
if ($debug) {
    print $query . "\n";
}

$query = "CREATE TEMPORARY TABLE check_pic_filenames (FileID int(10) unsigned ".
          "NOT NULL, Value text, PRIMARY KEY (FileID))";
$dbh->do($query);

if ($debug) {
    print $query . "\n";
}

$query = "INSERT INTO check_pic_filenames SELECT FileID, Value FROM ".
          "parameter_file WHERE ParameterTypeID=\@checkPicID AND ".    
          "Value IS NOT NULL";
$dbh->do($query);

if ($debug) {
    print $query . "\n";
}

my $extraWhere = "";
$extraWhere .= " AND f.FileID <= $maxFileID" if defined $maxFileID;
$extraWhere .= " AND f.FileID >= $minFileID" if defined $minFileID;

$query = "SELECT f.FileID FROM files AS f LEFT OUTER JOIN check_pic_filenames ".
         "AS c USING (FileID) WHERE c.FileID IS NULL AND f.FileType='mnc' ".
         $extraWhere;
if ($debug) {
    print $query . "\n";
}

my $horizontalPics = &NeuroDB::DBI::getConfigSetting(
                    \$dbh,'horizontalPics'
                    );
my $sth = $dbh->prepare($query);
$sth->execute();

while(my $rowhr = $sth->fetchrow_hashref()) {
    print "FileID from mass_pic.pl is: $rowhr->{'FileID'}\n" if $verbose;
    my $file = NeuroDB::File->new(\$dbh);
    $file->loadFile($rowhr->{'FileID'});

    unless(
        &NeuroDB::MRI::make_pics(
            \$file, $data_dir, 
            $pic_dir, $horizontalPics
        )
    ) {
        print "FAILURE!\n";
    }
}

$dbh->disconnect();

print "\nFinished mass_pic.pl execution\n" if $verbose;
exit 0;

1;

__END__

=pod

=head1 TO DO

Nothing planned.

=head1 BUGS

None reported.

=head1 LICENSING

License: GPLv3

=head1 AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

=cut