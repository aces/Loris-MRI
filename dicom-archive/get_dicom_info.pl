#!/usr/bin/env perl
#
# $Id: get_dicom_info.pl 8 2007-12-18 04:51:00Z zijdenbos $
#
# Routines for converting mri files to minc format. Must be included
# with routines for reading in data structures, specific to the input
# file format.
#

=pod

=head1 NAME

get_dicom_info.pl -- reads information out of the DICOM file headers

=head1 SYNOPSIS

perl get_dicom_info.pl [options] <dicomfile> [<dicomfile> ...]

Available options are:

-image    : print image number

-exam     : print exam number

-studyuid : print study UID

-series   : print series number

-echo: print echo number

-width: print width

-height: print height

-slicepos: print slice position

-slice_thickness: print slice thickness

-tr                : print repetition time (TR)

-te                : print echo time (TE)

-ti                : print inversion time (TI)

-date              : print acquisition date

-time              : print acquisition time

-file              : print file name

-pname             : print patient name

-pdob              : print patient date of birth

-pid               : print patient ID

-institution       : print institution name

-series_description: print series description

-sequence_name     : print sequence name

-scanner           : print scanner

-attvalue          : print the value(s) of the specified attribute

-stdin             : use STDIN for the list of DICOM files

-labels            : print one line of labels before the rest of the output

-error_string      : string to use for reporting empty fields


-verbose                : Be verbose if set

-version                : Print CVS version number and exit


=head1 DESCRIPTION

A tool to read information out of the DICOM file headers.


=head2 Methods

=cut


$VERSION = sprintf "%d", q$Revision: 8 $ =~ /: (\d+)/;

use FindBin;
use Getopt::Tabular qw(GetOptions);
use lib "$FindBin::Bin";
use DICOM::DICOM;
use NeuroDB::MRI;
use NeuroDB::ExitCodes;

my $Help;
my $Usage;
my @Variables = ();
my $ProgramName = $0;
my @input_list = ();
my $PrintLabels = 0;
my $PrintedLabels = 0;
my $ErrorString = 'UNDEF';
my $UseSTDIN = 0;

&CreateInfoText;
my @args = &SetupArgTables;
&GetOptions (\@args, \@ARGV, \@input_list) || die "\n";

if($UseSTDIN) {
    while(<STDIN>) {
        chomp $_;
        push @input_list, $_;
    }
}

if (@input_list <= 0)
{
    warn $Usage;
    die "Please specify one or more input DICOM files\n";
}

if(@Variables <= 0)
{
    warn $Usage;
    die "Please specify one or more fields to display\n";
}

my $isImage_hash = NeuroDB::MRI::isDicomImage(@input_list);
my @image_files  = grep { $$isImage_hash{$_} == 1 } keys %$isImage_hash;


foreach my $filename (@image_files) {
    my $dicom = DICOM->new();
    $dicom->fill($filename);

    # Get slice position and orientation (row and column vectors)
    my(@position) = 
	# ImagePositionPatient (0x0020, 0x0032)
        &convert_coordinates(&split_dicom_list(&trim($dicom->value('0020', '0032'))));
    my $computeSlicePos = grep($_->[1] eq 'slicepos', @Variables);
    if (scalar(@position) != 3 && $computeSlicePos) {
       warn "Warning: DICOM header (0020,0032) not found in $filename: "
           . "slice position cannot be computed. Skipping file.\n";
       push my @croft, $filename;
       next;
   }
    # ImageOrientationPatient (0x0020, 0x0037)
    my(@orientation) = &split_dicom_list(&trim($dicom->value('0020', '0037')));
    if (scalar(@orientation) != 6) {
       warn "************* Error reading slice orientation *************\n";
    }
    my(@column) = &convert_coordinates(@orientation[0..2]);
    my(@row) = &convert_coordinates(@orientation[3..5]);

    # Figure out normal and orientation
    my(@normal) = 
       &vector_cross_product(\@column, \@row);
    my @slc_dircos = &get_dircos(@normal);
    my $slicepos = &vector_dot_product(\@position, \@slc_dircos) if $computeSlicePos;

    # Print out variable labels
    if(!$PrintedLabels && $PrintLabels) {
	foreach $var (@Variables) {
	    if($$var[0] == -1) {
		print $$var[1]."\t";
	    } else {
		print $dicom->field(@$var, 'name')."\t";
	    }
	}
	print "\n";
	$PrintedLabels = 1;
    }

    # Print out the requested vars
    foreach $var (@Variables) {
	if($$var[0] == -1) {
	    if($$var[1] eq 'filename') {
		print $filename."\t";
	    } elsif($$var[1] eq 'slicepos') {
		print $slicepos."\t";
	    }
	} else {
	    if ($dicom->value(@$var) eq '') {
		print "$ErrorString\t";

	    }
	    else {
		print $dicom->value(@$var)."\t";
	    }
	}
    }
    print "\n";
    
}
&showcroft();


=pod

=head3 cleanup_and_die($message, $status)

Subroutine to clean up files and exit.

INPUTS:
  - $message: message to be printed in STDERR
  - $status : status code to use to exit the script

=cut

sub cleanup_and_die {

    # Get message to print and exit status
    local($message,$status) = @_;
    if (!defined($status)) {$status = 0;}
    if (defined($message)) {
        print STDERR $message;
        if ($message !~ /\n$/) {print STDERR "\n";}
    }

    $SIG{'INT'}  = 'IGNORE';
    $SIG{'TERM'} = 'IGNORE';
    $SIG{'QUIT'} = 'IGNORE';
    # Check for temp files
    if (defined($tmpdir) && -e $tmpdir) {
        print STDERR "Cleaning up temporary files.\n";
        system "rm -rf $tmpdir";
    }

    exit($status);
}

=pod

=head3 get_dircos()

Subroutine to get a direction cosine from a vector, correcting for
magnitude and direction if needed (the direction cosine should point
along the positive direction of the nearest axis).

RETURNS: X, Y and Z cosines

=cut

sub get_dircos {
    if (scalar(@_) != 3) {
        die "Argument error in get_dircos\n";
    }
    local($xcos, $ycos, $zcos) = @_;

    # Get magnitude
    local($mag) = sqrt($xcos**2 + $ycos**2 + $zcos**2);
    if ($mag <= 0) {$mag = 1};

    # Make sure that direction cosine is pointing along positive axis
    local($max) = $xcos;
    if (abs($ycos) > abs($max)) {$max= $ycos;}
    if (abs($zcos) > abs($max)) {$max= $zcos;}
    if ($max < 0) {$mag *= -1;}

    # Correct components
    $xcos /= $mag;
    $ycos /= $mag;
    $zcos /= $mag;

    return ($xcos, $ycos, $zcos);
}

=pod

=head3 convert_coordinates(@coords)

Routine that multiplies X and Y world coordinates by -1.

INPUT: array with world coordinates

RETURNS: array with converted coordinates

=cut

sub convert_coordinates {
    my(@coords) = @_;
    $coords[0] *= -1;
    $coords[1] *= -1;
    return @coords;
}

=pod

=head3 vector_dot_product($vec1, $vec2)

Routine to compute the dot product of two vectors.

INPUTS:
  - $vec1: vector 1
  - $vec2: vector 2

RESULTS: result of the dot product

=cut

sub vector_dot_product {
    my($vec1, $vec2) = @_;
    my($result, $i);
    $result = 0;
    for $i (0..2) {
        $result += $$vec1[$i] * $$vec2[$i];
    }
    return $result;
}

=pod

=head3 vector_cross_product($vec1, $vec2)

Routine to compute a vector cross product

INPUTS:
  - $vec1: vector 1
  - $vec2: vector 2

RESULTS: result of the vector cross product

=cut

sub vector_cross_product {
    my($vec1, $vec2) = @_;
    my(@result);
    $#result = 2;
    $result[0] = $$vec1[1] * $$vec2[2] - $$vec1[2] * $$vec2[1];
    $result[1] = $$vec1[2] * $$vec2[0] - $$vec1[0] * $$vec2[2];
    $result[2] = $$vec1[0] * $$vec2[1] - $$vec1[1] * $$vec2[0];
    return @result;
}

=pod

=head3 trim($input)

Remove leading and trailing spaces from the $input variable

INPUT: string to remove leading and trailing spaces from

RETURNS: string without leading and trailing spaces

=cut

sub trim {
    local($input) = @_;
    $input =~ s/^\s+//;
    $input =~ s/\s+$//;
    return $input;
}

=pod

=head3 showcroft()

Accessor for field C<@croft>.

=cut

sub showcroft {
    return @croft;
}

=pod

=head3 split_dicom_list($dlist)

Routine to split a DICOM list of values into a perl array using C<\\>.

INPUT: list of DICOM values

RETURNS: array of DICOM values if multiple values or DICOM value if only one value

=cut

sub split_dicom_list {
    my($dlist) = @_;
    my(@values) = split(/\\/, $dlist);
    foreach $value (@values) {
	$value += 0;
    }

    return (scalar(@values) > 1) ? @values : $values[0];
}

=pod

=head3 SetupArgTables()

To set up the arguments to the GetOpt table.

RETURNS: an array with all the options of the script

=cut

sub SetupArgTables
{
   my (@args) = 
       (
	["Slice info options", "section"],
	["-image", "call", ['0020','0013'], \&InfoOption,
	 "Print image number"],
	["-exam", "call", ['0020','0010'], \&InfoOption,
	 "Print exam number"],
        ["-studyuid", "call", ['0020','000D'], \&InfoOption,
         "Print study uid"],
        ["-series", "call", ['0020','0011'], \&InfoOption,
	 "Print series number"],
        ["-echo", "call", ['0018','0086'], \&InfoOption,
         "Print echo number"],
        ["-width", "call", ['0028','0011'], \&InfoOption,
         "Print width"],
        ["-height", "call", ['0028','0010'], \&InfoOption,
         "Print height"],
        ["-slicepos", "call", [-1,'slicepos'], \&InfoOption,
         "Print slice position"],
        ["-slice_thickness", "call", ['0018','0050'], \&InfoOption,
         "Print slice thickness"],
        ["-tr", "call", ['0018','0080'], \&InfoOption,
         "Print repetition time"],
        ["-te", "call", ['0018','0081'], \&InfoOption,
         "Print echo time"],
        ["-ti", "call", ['0018','0082'], \&InfoOption,
         "Print inversion time"],
        ["-date", "call", ['0008','0022'], \&InfoOption,
         "Print acquisition date"],
        ["-time", "call", ['0008','0032'], \&InfoOption,
         "Print acquisition time"],
        ["-file", "call", [-1,'filename'], \&InfoOption,
         "Print filename"],

        ["Patient info options", "section"],
        ["-pname", "call", ['0010','0010'], \&InfoOption,
         "Print patient name"],
        ["-pdob", "call", ['0010','0030'], \&InfoOption,
         "Print patient date of birth"],
        ["-pid", "call", ['0010','0020'], \&InfoOption,
         "Print patient id"],

        ["Other info options", "section"],
        ["-institution", "call", ['0008','0080'], \&InfoOption,
         "Print institution name"],
	["-series_description", "call", ['0008','103E'], \&InfoOption,
	 "Print series description"],
	["-sequence_name", "call", ['0018','0024'], \&InfoOption,
	 "Print sequence name"],
	["-scanner", "call", ['0008','1090'], \&InfoOption,
	 "Print scanner"],
        ["-attvalue", "call", undef, \&TwoArgInfoOption,
         "Print the value(s) of the specified attribute"],
        ["-stdin", "boolean", 1, \$UseSTDIN,
         "Use STDIN for the list of dicom files"],

        ["Formatting options", "section"],
	["-labels", "boolean", 1, \$PrintLabels,
	 "Print one line of labels before the rest of the output"],
	["-error_string", "string", 1, \$ErrorString,
	 "String to use for reporting empty fields"],
	);
	
   return @args;
}

=pod

=head3 InfoOption(@addr)

Greps the group and element information from the GetOpt table options specified.

INPUTS:
  - $option: name of the option
  - $rest  : reference to the remaining arguments of the command line
  - @addr  : array reference with DICOM group & element from the GetOpt option

=cut

sub InfoOption {
    my ($option, $rest, @addr) = @_;
    
    my $group = shift @addr;
    my $element = shift @addr;
    push(@Variables, [$group, $element]);

    1;
}

=pod

=head3 TwoArgInfoOption($option, $rest)

Greps the group and element information from the GetOpt table options specified
and checks that the two arguments required by the option have been set.

INPUTS:
  - $option: name of the option that requires two arguments
  - $rest  : array with group and element information from the GetOpt table

=cut

sub TwoArgInfoOption {
    my ($option, $rest) = @_;
    
    my $group = shift @$rest;
    my $element = shift @$rest;

    if (!defined($element) || !defined($group)) {
        &cleanup_and_die(
            "$option requires two arguments",
            $NeuroDB::ExitCodes::MISSING_ARG
        );
    }

    push(@Variables, [$group, $element]);

    1;
}

=pod

=head3 CreateInfoText()

Creates the information text to be displayed by GetOpt to describe the script/

=cut

sub CreateInfoText
{
   $Usage = <<USAGE;
Usage: get_dicom_info [options] <dicomfile> [<dicomfile> ...]
       get_dicom_info -help

USAGE

   $Help = <<HELP;
get_dicom_info reads info out of the DICOM file headers, based on some code chunks written by Peter Neelin for dicom_to_minc.

  Author:        Jonathan Harlap
  Date:          2003/01/16
  Last modified: 2003/01/31

HELP

   &Getopt::Tabular::SetHelp ($Help, $Usage);
}

=pod

=head1 LICENSING

License: GPLv3

=head1 AUTHORS

Jonathan Harlap,
LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative
Neuroscience

=cut
