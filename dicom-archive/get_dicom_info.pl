#!/usr/bin/env perl
#
# $Id: get_dicom_info.pl 8 2007-12-18 04:51:00Z zijdenbos $
#
# Routines for converting mri files to minc format. Must be included
# with routines for reading in data structures, specific to the input
# file format.
#
$VERSION = sprintf "%d", q$Revision: 8 $ =~ /: (\d+)/;

use FindBin;
use Getopt::Tabular qw(GetOptions);
use lib "$FindBin::Bin";
use DICOM::DICOM;
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

foreach my $filename (@input_list) {
    my $dicom = DICOM->new();
    $dicom->fill($filename);

    # Get slice position and orientation (row and column vectors)
    my(@position) = 
	# ImagePositionPatient (0x0020, 0x0032)
        &convert_coordinates(&split_dicom_list(&trim($dicom->value('0020', '0032'))));
    if (scalar(@position) != 3) {
       warn "Warning: The file: $filename is not DICOM!\n";
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
    my $slicepos = &vector_dot_product(\@position, \@slc_dircos);

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

# Subroutine to clean up files and exit
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

# Subroutine to get a direction cosine from a vector, correcting for
# magnitude and direction if needed (the direction cosine should point
# along the positive direction of the nearest axis)
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

# Routine to convert world coordinates
sub convert_coordinates {
    my(@coords) = @_;
    $coords[0] *= -1;
    $coords[1] *= -1;
    return @coords;
}

# Routine to compute a dot product
sub vector_dot_product {
    my($vec1, $vec2) = @_;
    my($result, $i);
    $result = 0;
    for $i (0..2) {
        $result += $$vec1[$i] * $$vec2[$i];
    }
    return $result;
}

# Routine to compute a vector cross product
sub vector_cross_product {
    my($vec1, $vec2) = @_;
    my(@result);
    $#result = 2;
    $result[0] = $$vec1[1] * $$vec2[2] - $$vec1[2] * $$vec2[1];
    $result[1] = $$vec1[2] * $$vec2[0] - $$vec1[0] * $$vec2[2];
    $result[2] = $$vec1[0] * $$vec2[1] - $$vec1[1] * $$vec2[0];
    return @result;
}

sub trim {
    local($input) = @_;
    $input =~ s/^\s+//;
    $input =~ s/\s+$//;
    return $input;
}

sub showcroft {
    return @croft;
}

# Routine to split a DICOM list into a perl list
sub split_dicom_list {
    my($dlist) = @_;
    my(@values) = split(/\\/, $dlist);
    foreach $value (@values) {
	$value += 0;
    }

    return (scalar(@values) > 1) ? @values : $values[0];
}

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


sub InfoOption {
    my ($option, $rest, @addr) = @_;
    
    my $group = shift @addr;
    my $element = shift @addr;
    push(@Variables, [$group, $element]);

    1;
}

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

