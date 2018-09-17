#!/usr/bin/perl 
# Jonathan Harlap 2006
# jharlap@bic.mni.mcgill.ca
# Perl tool to update headers in a dicomTar archive en masse.
# $Id: updateHeadersBatch.pl 4 2007-12-11 20:21:51Z jharlap $

=pod

=head1 NAME

updateHeadersBatch.pl -- updates DICOM headers for an entire study or a
specific series in a DICOM archive


=head1 SYNOPSIS

perl tools/updateHeadersBatch.pl C<[options]> C<[/path/to/DICOM/or/TARCHIVE]>

Available options are:

-keys    : The number of key fields in the spec file, used to define the
			matching... Note that 1 key consists of two columns, the first
			being the field name (formatted as '(XXXX,YYYY)') and the second
			being its value.

-specfile: The specifications file. Format is one series per line, tab
            separated fields. First field is the series number. Then every
            pair of fields is the DICOM field name (as known to C<dcmtk>) and
            new value, respectively.

-database: Enable C<dicomTar>'s database features

-profile : Name of the config file in C<../dicom-archive/.loris_mri>

-verbose : Be verbose

-version : Print version and revision number and exit

=head1 DESCRIPTION

A script that updates DICOM headers for an entire study or a specific series
in a DICOM archive. If run with the C<-database> option, it will update the
C<tarchive> tables with the updated DICOM archive.


=head1 TODO

Make sure this works as expected.

=head1 LICENSING

License: GPLv3

=head1 AUTHORS

Jonathan Harlap, LORIS community <loris.info@mcin.ca> and McGill Centre for
Integrative Neuroscience

=cut

use strict;

use Cwd qw/ abs_path /;
use File::Basename qw/ dirname /;
use File::Find;
use File::Temp qw/ tempdir /;
use Getopt::Tabular;

use Data::Dumper;

use DICOM::DICOM;
use NeuroDB::DBI;
use NeuroDB::ExitCodes;

my $verbose = 0;
my $database = 0;
my $profile    = undef;
my @leftovers = ();
my $specfile = undef;
my $keyCols = 1;

my $Usage = "------------------------------------------

$0 updates DICOM headers for an entire study or a specific series in a dicomTar archive.

Usage:\n\t $0 </PATH/TO/ARCHIVE> -specfile <SPECFILE> [options]
\n\n See $0 -help for more info\n\n";

my @arg_table =
	 (
	  ["Main options", "section"],
      ["-keys", "integer", 1, \$keyCols, "The number of key fields in the spec file, used to define the matching...  Note that 1 key consists of two columns, the first being the field name (formatted as '(XXXX,YYYY)') and the second being its value."],
      ["-specfile", "string",1, \$specfile, "The specifications file.  Format is one series per line, tab separated fields.  First field is the series number.  Then every pair of fields is the DICOM field name (as known to dcmtk) and new value, respectively."],

	  ["General options", "section"],
	  ["-database", "boolean", 1, \$database, "Enable dicomTar's database features"],
	  ["-profile","string",1, \$profile, "Specify the name of the config file which resides in .loris_mri in the current directory"],
	 
	  ["-verbose", "boolean", 1, \$verbose, "Be verbose."],
	  ["-version", "call", undef, \&handle_version_option, "Print version and revision number and exit"],
		);


# Parse arguments
&GetOptions(\@arg_table, \@ARGV, \@leftovers) || exit 1;

unless((scalar(@leftovers) == 1) && defined($specfile) ) {
	 print $Usage;
	 exit(1);
}

################################################################
################### input option error checking ################
################################################################
if ( !$profile ) {
	print $Usage;
	print STDERR "$Usage\n\tERROR: missing -profile argument\n\n";
	exit $NeuroDB::ExitCodes::PROFILE_FAILURE;
}
{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/$profile" }
if ( !@Settings::db ) {
	print STDERR "\n\tERROR: You don't have a \@db setting in the file "
		. "$ENV{LORIS_CONFIG}/.loris_mri/$profile \n\n";
	exit $NeuroDB::ExitCodes::DB_SETTINGS_FAILURE;
}

# connect to the database
my $dbh         = &NeuroDB::DBI::connect_to_db(@Settings::db);
my $bin_dirPath = NeuroDB::DBI::getConfigSetting(\$dbh,'MRICodePath');
$bin_dirPath    =~ s/\/$//;

my %setTable;
my @keys;
parse_specfile($specfile, $keyCols, \@keys, \%setTable);

my $tarchive = abs_path($leftovers[0]);

# create the temp dir
my $tempdir = tempdir( CLEANUP => 1 );

# extract the tarchive
my $dcmdir = &extract_tarchive($tarchive, $tempdir);

# go through the files, modifying as needed
my $find_handler = sub {
    my $file = $File::Find::name;
    if(-f $file) {
        
        # read the file, assuming it is dicom
        my $dicom = DICOM->new();
        $dicom->fill($file);
        my $fileIsDicom = 1;
        my $studyUID = $dicom->value('0020','000D');
        
        # see if the file was really dicom
        if($studyUID eq "") {
            $fileIsDicom = 0;
        }
        
        if($fileIsDicom) {
            my $keyhash = "";
            for(my $i = 0; $i < $keyCols; $i++) {
                my $val = trimwhitespace($dicom->value(@{$keys[$i]}));
                $keyhash .= $val."---";
            }

            print "KEYHASH: $keyhash\n" if $verbose;

            if(defined($setTable{$keyhash})) {
                print "UPDATING\n" if $verbose;
                update_file_headers($file, $setTable{$keyhash});
            }
        }
    }
};

find($find_handler, "$tempdir/$dcmdir");

# rebuild the tarchive
print "Rebuilding tarchive\n" if $verbose;
my $targetdir = dirname($tarchive);
my $DICOMTAR = $bin_dirPath . "/dicom-archive/dicomTar.pl";
my $cmd = "$DICOMTAR $tempdir/$dcmdir $targetdir -clobber";
if($database) {
	 $cmd .= " -database";
}
if(defined($profile)) {
	$cmd .= " -profile $profile";
}

print "Executing $cmd\n" if $verbose;
`$cmd`;
my $exitCode = $?>> 8;
if($exitCode != 0) {
	 print "Error occurred during dicomTar!  Exit code was $exitCode\n" if $verbose;
	 exit 1;
}

exit 0;

sub parse_specfile {
    my ($specfile, $keyCols, $keyListRef, $setTableRef) = @_;

    open SPECS, $specfile or die "Could not open specfile '$specfile'\n";
    my $madeKeyList = 0;
    while(my $line = <SPECS>) {
        chomp($line);
        if((length($line) == 0) || ($line =~ /^\#/)) { next; };
        my @bits = split(/\t/, $line);

        my @setList = ();
        my $key = "";
        for(my $i=0; $i<$keyCols*2; $i+=2) {
            if($bits[$i] =~ /\(([0-9a-fA-F]{4}),([0-9a-fA-F]{4})\)/) {
                unless($madeKeyList) {
                    my @keyList = ($1, $2);
                    push @$keyListRef, \@keyList;
                }
                
                $key .= $bits[$i+1] . "---";
            }
        }

        $madeKeyList = 1;

        for(my $i=$keyCols*2; $i<$#bits; $i+=2) {
            push @setList, [$bits[$i], $bits[$i+1]];
        }
        $setTableRef->{$key} = \@setList;
    }
}
    

sub extract_tarchive {
	 my ($tarchive, $tempdir) = @_;

	 print "Extracting tarchive\n" if $verbose;
	 `cd $tempdir ; tar -xf $tarchive`;
	 opendir TMPDIR, $tempdir;
	 my @tars = grep { /\.tar\.gz$/ && -f "$tempdir/$_" } readdir(TMPDIR);
	 closedir TMPDIR;

	 if(scalar(@tars) != 1) {
		  print "Error: Could not find inner tar in $tarchive!\n";

		  print @tars . "\n";
		  exit(1);
	 }

	 my $dcmtar = $tars[0];
	 my $dcmdir = $dcmtar;
	 $dcmdir =~ s/\.tar\.gz$//;

	 `cd $tempdir ; tar -xzf $dcmtar`;
	 
	 return $dcmdir;
}

sub update_file_headers {
	 my ($file, $setRef) = @_;
	 
	 # if there was already a backup file, dcmodify would crush it...
	 my $protectedFile;
	 my $backupFile = "${file}.bak";
	 if(-f $backupFile) {
		  (undef, $protectedFile) = tempfile('tempXXXXX', OPEN => 0);
		  `mv '$backupFile' '$protectedFile'`;
	 }

	 my $cmd = "dcmodify ";
	 foreach my $set (@$setRef) {
		  $cmd .= " --insert-tag '".$set->[0]."=".$set->[1]."' ";
	 }
	 $cmd .= "'${file}' 2>&1";
	 
	 `$cmd`;

	 if(defined($protectedFile)) {
		  `mv '$protectedFile' '$backupFile'`;
	 } else {
		  unlink $backupFile;
	 }
}

sub handle_version_option {
	 my ($opt, $args) = @_;

	 my $versionInfo = sprintf "%d", q$Revision: 4 $ =~ /: (\d+)/;
	 print "Version $versionInfo\n";
	 exit(0);
}

sub trimwhitespace {
	my $string = shift;
	$string =~ s/^\s+//;
	$string =~ s/\s+$//;
	return $string;
}
