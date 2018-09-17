#!/usr/bin/perl 

=pod

=head1 NAME

splitMergedSeries.pl -- a script that goes through the supplied directory
with DICOM files (or the supplied DICOM archive) and generates a specfile which
can be used to fix the DICOM fields of difficult to separate series.


=head1 SYNOPSIS

perl tools/splitMergedSeries.pl C<[options]> C<[/path/to/DICOM/or/TARCHIVE]> C<[specfile_name]>

Available options are:

-series : Split series by generating new series numbers [default]

-seqnam : Split series by modifying the sequence name

-echo   : Split series by generating new echo numbers

-clobber: Overwrite the existing C<specfile>

-verbose: Be verbose

-debug  : Be even more verbose


=head1 DESCRIPTION

This script goes through the supplied directory with DICOM files (or supplied
DICOM archive) and generates a C<specfile> which can be used to fix the DICOM
fields of difficult to separate series. Specifically, the specfile will:

1. Insert C<EchoNumber> values in case this field was not set for a
   multi-echo sequence
2. Insert or modify a field if multiple repeats of the same sequence are
   present (and not otherwise separated). The user can select which field
   is modified by selecting one of the sequence splitting options.

The resulting C<specfile> can be used as input to C<updateHeadersBatch.pl>.


=head1 TODO

Make fully sure this works as expected.

=head1 LICENSING

License: GPLv3

=head1 AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative
Neuroscience

=cut

use strict;
use Cwd qw/ abs_path /;
use File::Basename qw/ basename /;
use File::Temp qw/ tempdir /;
use Getopt::Tabular;
use DICOM::DICOM qw/ dicom_fields dicom_private /;
use IO::File;

$|++;

my $Verbose = 1;
my $Clobber = 0;
my $Execute = 1;
my $Debug   = 0;
my @Leftovers = ();
my $SplitField = 'SeriesNumber';

my $Help = <<HELP;

Goes through the supplied directory with DICOM files or supplied tarchive
and generates a specfile which can be used to fix the DICOM fields of 
difficult to separate series. Specifically, the specfile will 

1. Insert EchoNumber values in case this field was not set for a 
   multi-echo sequence
2. Insert or modify a field if multiple repeats of the same sequence are
   present (and not otherwise separated). The user can select which field
   is modified by selecting on of the sequence splitting options.

The resulting specfile can be used as input to updateHeadersBatch.pl.

HELP

my $Usage = <<USAGE;

$0 generates a specfile to insert EchoNumber values and modify specific fields in case repeats of the same series are present.

Usage:\n\t$0 </PATH/TO/DCMFolder>|<tarchive> <specfile> 
\n  See $0 -help for more info\n
USAGE

my @ArgTable = (
    ["Sequence splitting options", "section"],
    ["-series", "const", 'SeriesNumber', \$SplitField, 
     "Split series by generating new series numbers [default]"],
    ["-seqnam", "const", 'SequenceName', \$SplitField, 
     "Split series by modifying the sequence name"],
    ["-echo", "const", 'EchoNumber', \$SplitField, 
     "Split series by generating new echo numbers"],
    ["General options", "section"],
    ["-clobber", "boolean", 1, \$Clobber, 
     "Overwrite existing specfile"],
    ["-verbose|-quiet", "boolean", 1, \$Verbose, "Be verbose"],
    ["-debug", "boolean", 1, \$Debug, "Be even more verbose"],
    );

&Getopt::Tabular::SetHelp($Help, $Usage);

&GetOptions(\@ArgTable, \@ARGV, \@Leftovers) || exit 1;

die $Usage unless(scalar(@Leftovers) == 2);

$Verbose = 1 if $Debug;

my $Dir = abs_path($Leftovers[0]);
my $SpecFile = $Leftovers[1];

die "File $SpecFile exists; use -clobber to overwrite\n"
    if (-f $SpecFile && ! $Clobber);

if (-f $Dir) {
    # We're dealing with a tarchive (hopefully)
    # create the temp dir
    my $tempdir = File::Spec->tmpdir();
    $tempdir    = tempdir( "${tempdir}/sMS-XXXXX", CLEANUP => 1 );

    # extract the tarchive
    $Dir = &extract_tarchive($Dir, $tempdir);

    $Dir = "${tempdir}/$Dir";
}
elsif (! -d $Dir) {
    die "Argument $Dir does not appear to be a directory or a file\n";
}

# Get relevant dicom fields and sort first by echo time, then image number
my @ParamList = `find $Dir -type f | get_dicom_info.pl -stdin -studyuid -series -series_description -sequence_name -tr -te -image -echo -slicepos -slice_thickness`;

die "Unable to extract any parameters from the files in $Dir; this doesn't look good\n"
    if (! @ParamList);

# Collect info from all slices 
# This could no doubt be written much more elegantly using sorts and
# the like, but the hashes allow for some very explicit sanity checks
my %S;
my %AllSeries;
my @NewSeries;
foreach my $params (@ParamList) {
    my ($stuid, $sernum, $sdesc, $seqnam, $tr, $te, $im, $echo, $slicepos, 
	$slicethick) = split(/\t/, $params);
    
    $AllSeries{$sernum} = 1;

    my $ser = "${stuid}::${sernum}";

    if (! defined $S{$ser}) {
	# Haven't seen this series before, so register it
	$S{$ser} = {
	    SDESC  => $sdesc,
	    SEQNAM => $seqnam,
	    TR     => $tr,
	    SLTHK  => $slicethick,
	    TE     => {
		$te => {
		    ECHO => $echo,
		    IMS  => {
			$im => $slicepos,
		    }
		}
	    }
	};
    }
    else {
	# Previously seen series found - perform some sanity checks
	# Series description should really be the same.
	die "Unexpected: multiple series descriptions found for series ${ser}:\n\t$S{$ser}{SDESC} and $sdesc\n"
	    if $S{$ser}{SDESC} ne $sdesc;

	# Sequence name should really be the same.
	die "Unexpected: multiple sequence names found for series ${ser}:\n\t$S{$ser}{SEQNAM} and $seqnam\n"
	    if $S{$ser}{SEQNAM} ne $seqnam;

	# TR should really be the same.
	die "Unexpected: multiple TRs found for series ${ser}:\n\t$S{$ser}{TR} and $tr\n"
	    if $S{$ser}{TR} != $tr;

	# Slice thickness should really be the same.
	die "Unexpected: multiple slice thicknesses found for series ${ser}:\n\t$S{$ser}{SLTHK} and $slicethick\n"
	    if $S{$ser}{TR} != $tr;

	# If TE is new, store it
	if (! defined $S{$ser}{TE}{$te}) {
	    $S{$ser}{TE}{$te} = {
		ECHO => $echo,
		IMS  => {
		    $im => $slicepos,
		}
	    }
	}
	else {
	    # Previously seen TE - perform sanity checks
	    # Whatever the echo number is, it should be the same
	    die "Unexpected: multiple echo numbers found for the same TE in series ${ser}:\n\t$S{$ser}{TE}{$te}{ECHO} and $echo\n"
		if $S{$ser}{TE}{$te}{ECHO} ne $echo;

	    # At this level image numbers should be unique
	    die "Unexpected: duplicate image numbers found for series ${ser}: $im\n"
		if (defined $S{$ser}{TE}{$te}{IMS}{$im});

	    # Add this image to the list
	    $S{$ser}{TE}{$te}{IMS}{$im} = $slicepos;
	}
    }
}

# Now see if we have anything to fix and generate a specfile
my @Spec = "\# KeyCols: 3\n";
foreach my $ser (keys %S) {
    if ($Debug) {
	print "\nStudyuid::sernum: $ser\n";
	print "\tserdesc: $S{$ser}{SDESC}\n";
	print "\tseqnam:  $S{$ser}{SEQNAM}\n";
	print "\tTR:      $S{$ser}{TR}\n";
    };

    my ($stuid, $sernum) = split('::', $ser);

    # Reset NewSeries as this is only used to keep new series numbers
    # which match subseries for each echo
    @NewSeries = ();
    my $echoctr = 0;
    my @TE = sort keys %{ $S{$ser}{TE} };
    foreach my $te (@TE) {
	$echoctr++;
	my $echo = $S{$ser}{TE}{$te}{ECHO};
	if ($Debug) {
	    print "\t\tTE:   $te\n";
	    print "\t\tECHO: $echo\n";
	}
	
	# If this series has multiple echoes without echo numbers,
	# generate a new echo number
	if ((@TE > 1) && ($echo =~ /UNDEF/)) {
	    push(@Spec, specstring('SeriesNumber', $sernum,
				   'StudyInstanceUID', $stuid,
				   'EchoTime', $te,
				   'EchoNumber', $echoctr));
	    
	    if ($Debug) {
		print "\t\t\t=> $echoctr\n";
	    }
	}
	
	# Look for breaks in the slice position series
	my @imgs = &split_on_slicepos_breaks($S{$ser}{TE}{$te}{IMS}, 
					     $S{$ser}{SLTHK});

	# If this series was made up of multiple sub-acquisitions,
	# generate new fields for the duplicate sub-series
	for my $subseriesctr (0 .. $#imgs) {

	    print "\t [ @{ $imgs[$subseriesctr] } ],\n" if ($Debug);

	    my ($key, $value);
	    foreach my $im (@{ $imgs[$subseriesctr] }) {
		($key, $value) = new_sub_series($sernum,
						$S{$ser}{SEQNAM},
						$echoctr,
						$subseriesctr);

		if (defined $value) {
		    push(@Spec, specstring('SeriesNumber', $sernum,
					   'StudyInstanceUID', $stuid,
					   'ImageNumber', $im,
					   $key, $value));
		}
	    }
	    
	    if (defined $value) {
		print "\t\t$key => $value\n" if ($Debug);

		# Only update the list of used series here to make sure
		# the same new unique series is used for all images that
		# belong to it
		$AllSeries{$value} = 1;
	    }
	    
	    $subseriesctr++;
	}
    }
    
    # Don't allow only some of the echoes being numbered
    die "Unexpected: series ${ser} has multiple echoes, but only some of them were numbered\n"
	if ((@TE > 1) && (@TE != $echoctr));
}

if (@Spec > 1) {
    print "SPECFILE:\n@Spec\n" if ($Debug);

    my $specfh = new IO::File "> $SpecFile";
    
    die "Unable to create $SpecFile\n" if ! defined $specfh;

    print $specfh @Spec;

    $specfh->close;
}
else {
    print "Nothing to do; no specfile generated\n" if $Verbose;
}



# Subroutines--------------------------------------------------

sub extract_tarchive {
    my ($tarchive, $tempdir) = @_;
    
    print "Extracting tarchive $tarchive to ${tempdir}/\n" if $Verbose;
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

sub split_on_slicepos_breaks {
    my $ims = shift @_;
    my $slicethick = shift @_;

    $slicethick = undef if ($slicethick != /^\d+$/);

    my @imlist;

    my (@sorted) = sort {$a <=> $b} keys %$ims;

    # No need to bother for a single slice
    return @sorted if (@sorted < 2);
    
    # Get the slice positions, sorted by image number
    my @pos = @$ims{@sorted};

    my $group = 0;
    push (@{$imlist[$group]}, $sorted[0]);

    # Set the initial movement direction to undef
    my $dir = undef;

    for my $i (1 .. $#sorted) {
	my $delta = $pos[$i] - $pos[$i-1];

	# Set the movement direction. Leave it as undef if delta = 0
	# (two slices at the same position)
	if ((! defined $dir) && $delta) {
	    $dir = $delta / abs($delta);
	}

	# Set the slicethickness if it was not (yet) defined
	if ((! defined $slicethick) && $delta) {
	    $slicethick = abs($delta);
	}

	# Start a new group if
	# - slices are at (effectively) in the same location
	# - step is much smaller than expected
	# - step is much larger than expected
	# - direction has changed
	if ((abs($delta) < 1e-5) || 
	    (abs($delta) < 0.1 * $slicethick) ||
	    (abs($delta) > 1.5 * $slicethick) ||
	    ($dir > 0 && $delta < 0) ||  
	    ($dir < 0 && $delta > 0)) {
	    
	    $group++;

	    # Unset the direction so it will be recalculated for the next group
	    $dir = undef;
	}
	
	push (@{$imlist[$group]}, $sorted[$i]);
    }

    return @imlist;
}

sub new_sub_series {
    my ($sernum, $seqnam, $echoctr, $subseriesctr) = @_;

    my $value = undef;

    if ($SplitField eq 'SeriesNumber') {
	if ($subseriesctr) {
	    # Series numbers can stay the same for the first subseries, so
	    # only do something for subsequent ones
	    if ($echoctr > 1) {
		# For subsequent echoes, use existing values
		$value = $NewSeries[$subseriesctr];
	    }
	    else {
		# For the first echo, generate a new unique series number
		$value = $sernum;
		$value++ while (defined $AllSeries{$value});
		$NewSeries[$subseriesctr] = $value;
	    }
	}
    }
    elsif ($SplitField eq 'SequenceName') {
	# Append a letter to the sequence name
	$value = "${seqnam}_" . ('a'..'z')[$subseriesctr-1] if ($subseriesctr);
    }
    elsif ($SplitField eq 'EchoNumber') {
	# For each new subseries, increase the echo number by 100
	# So for repeated dual-echo series, one would get echoes 1 and 2,
	# followed by 101 and 102, 201 and 202, etc.
	$value = 100 * $subseriesctr + $echoctr;
    }
    else {
	die "Error: unknown splitting field $SplitField supplied\n";
    }

    return ($SplitField, $value);
}

sub fieldByName {
    my $name = shift @_;
    
    my @dictEntries = grep(/\s$name$/, @DICOM::dicom_fields, @DICOM::dicom_private);

    die "Unable to locate fields for variable $name\n"
	if (! @dictEntries);
    
    die "Ambiguous field name $name used:\n\t" . join("\n\t", @dictEntries) . "\n"
	if (@dictEntries > 1);

    my ($group, $elem, $code, $numa, $name) = split(/\s+/, $dictEntries[0]);
    
    return ($group, $elem);
}

sub specstring {
    my @list = @_;

    die "Error: argument to spectring() has " . scalar(@list) . " elements; should be an even number larger than 2\n"
	if ((@list < 2) || (@list % 2));
    
    my $spec = '';
    my $i = 0;
    while ($i < $#list) {
	my $name  = $list[$i];
	my $value = $list[$i+1];

	my ($group, $elem) = fieldByName($name);

	$spec .= "(${group},${elem})\t$value\t";

	$i += 2;
    }

    chomp $spec;
    $spec .= "\n";
    
    return $spec;
}

sub Run {
    my(@cmd) = @_;

    print "@cmd\n" if $Verbose;

    if ($Execute) {
        system(@cmd) && die "@cmd failed: $?\n";
    }
}
