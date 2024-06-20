#! /usr/bin/env perl
#
# linear fitting using parameters optimised by Claude Lepage,
# using a brain mask for the source and the target. The best
# way to run this script is to use -nmi with only the target
# brain mask applied on the last fitting stage.
# This was greatly inspired by best1stepnlreg.pl by Steve Robbins.
#
# Claude Lepage - claude@bic.mni.mcgill.ca
# Andrew Janke - rotor@cmr.uq.edu.au
# Center for Magnetic Resonance
# The University of Queensland
# http://www.cmr.uq.edu.au/~rotor
#
# Copyright Alan C. Evans
# Professor of Neurology
# McGill University
#

use strict;
use warnings "all";
use Getopt::Tabular;
use File::Basename;
use File::Temp qw/ tempdir /;

my @conf = (

   { type        => "blur",       # -lsq7 scaling only
     trans       => [qw/-est_translations/],
     blur_fwhm   => 8,
     steps       => [qw/4 4 4/],
     tolerance   => 0.0001,
     simplex     => 16 },

   { type        => "blur",       # -lsqXX full options
     trans       => undef,
     blur_fwhm   => 8,
     steps       => [qw/4 4 4/],
     tolerance   => 0.0001,
     simplex     => 16 },

   { type        => "blur",
     trans       => undef,
     blur_fwhm   => 4,
     steps       => [qw/4 4 4/],
     tolerance   => 0.0001,
     simplex     => 8 },

   { type        => "blur",
     trans       => undef,
     blur_fwhm   => 2,
     steps       => [qw/2 2 2/],
     tolerance   => 0.0005,
     simplex     => 4 },

   );


my($Help, $Usage, $me);
my(@opt_table, %opt, $source, $target, $outxfm, $outfile, @args, $tmpdir);

$me = &basename($0);
%opt = (
   'verbose'   => 1,
   'clobber'   => 0,
   'fake'      => 0,
   'init_xfm'  => undef,
   'source_mask' => undef,
   'target_mask' => undef,
   'lsqtype'     => "-lsq9",
   'objective'   => "-xcorr"
   );

$Help = <<HELP;
| $me does hierachial linear fitting between two files.
|    you will have to edit the script itself to modify the
|    fitting levels themselves
| 
| Problems or comments should be sent to: claude\@bic.mni.mcgill.ca
HELP

$Usage = "Usage: $me [options] source.mnc target.mnc output.xfm [output.mnc]\n".
         "       $me -help to list options\n\n";

@opt_table = (
   ["-verbose", "boolean", 0, \$opt{verbose},
      "be verbose" ],
   ["-clobber", "boolean", 0, \$opt{clobber},
      "clobber existing check files" ],
   ["-fake", "boolean", 0, \$opt{fake},
      "do a dry run, (echo cmds only)" ],
   ["-init_xfm", "string", 1, \$opt{init_xfm},
      "initial transformation [default identity]" ],
   ["-source_mask", "string", 1, \$opt{source_mask},
      "source mask to use during fitting (on last stage only)" ],
   ["-target_mask", "string", 1, \$opt{target_mask},
      "target mask to use during fitting (on last stage only)" ],
   ["-lsq6", "const", "-lsq6", \$opt{lsqtype},
      "use 6-parameter transformation" ],
   ["-lsq7", "const", "-lsq7", \$opt{lsqtype},
      "use 7-parameter transformation" ],
   ["-lsq9", "const", "-lsq9", \$opt{lsqtype},
      "use 9-parameter transformation [default]" ],
   ["-lsq12", "const", "-lsq12", \$opt{lsqtype},
      "use 12-parameter transformation" ],
   ["-mi", "const", "-mi", \$opt{objective},
      "use mutual information as objective function [default -xcorr]" ],
   ["-nmi", "const", "-nmi", \$opt{objective},
      "use normalized mutual information as objective function [default -xcorr]" ]
   );

# Check arguments
&Getopt::Tabular::SetHelp($Help, $Usage);
&GetOptions (\@opt_table, \@ARGV) || exit 1;
die $Usage if(! ($#ARGV == 2 || $#ARGV == 3));
$source = shift(@ARGV);
$target = shift(@ARGV);
$outxfm = shift(@ARGV);
$outfile = (defined($ARGV[0])) ? shift(@ARGV) : undef;

# check for files
die "$me: Couldn't find input file: $source\n\n" if (!-e $source);
die "$me: Couldn't find input file: $target\n\n" if (!-e $target);
if(-e $outxfm && !$opt{clobber}){
   die "$me: $outxfm exists, -clobber to overwrite\n\n";
   }
if(defined($outfile) && -e $outfile && !$opt{clobber}){
   die "$me: $outfile exists, -clobber to overwrite\n\n";
   }

my $mask_warning = 0;
if( !defined($opt{source_mask}) ) {
  $mask_warning = 1;
} else {
  if( !-e $opt{source_mask} ) {
    $mask_warning = 1;
  }
}
if( !defined($opt{target_mask}) ) {
  $mask_warning = 1;
} else {
  if( !-e $opt{target_mask} ) {
    $mask_warning = 1;
  }
}
if( $mask_warning == 1 ) {
  print "Warning: For optimal results, you should use masking.\n";
  print "$Usage";
}

# make tmpdir
$tmpdir = &tempdir( "$me-XXXXXXXX", TMPDIR => 1, CLEANUP => 1 );

# set up filename base
my($i, $s_base, $t_base, $tmp_xfm, $tmp_source, $tmp_target, $prev_xfm);
$s_base = &basename($source);
$s_base =~ s/\.mnc(.gz)?$//;
$s_base = "S${s_base}";
$t_base = &basename($target);
$t_base =~ s/\.mnc(.gz)?$//;
$t_base = "T${t_base}";

# Mask the source and target once before blurring. Both masks must exist.

my $source_masked = $source;
my $target_masked = $target;

if( defined($opt{source_mask}) and defined($opt{target_mask}) ) { 
  if( -e $opt{source_mask} and -e $opt{target_mask} ) {
    $source_masked = "${tmpdir}/${s_base}_masked.mnc";
    &do_cmd( 'minccalc', '-clobber',
             '-expression', 'if(A[1]>0.5){out=A[0];}else{out=A[1];}',
             $source, $opt{source_mask}, $source_masked );

    $target_masked = "${tmpdir}/${t_base}_masked.mnc";
    &do_cmd( 'minccalc', '-clobber',
             '-expression', 'if(A[1]>0.5){out=A[0];}else{out=A[1];}',
             $target, $opt{target_mask}, $target_masked );
  }
}

# initial transformation supplied by the user.

$prev_xfm = ( defined $opt{init_xfm} && -e $opt{init_xfm} ) ?
            $opt{init_xfm} : undef;

# do a centering of the image first. Somehow, I think that minctracc should
# be able to do this on its own.

if( !defined( $prev_xfm ) ) {
  my ($sxc,$syc,$szc) = split( ' ', `mincstats -quiet -com -world_only $source` );
  my ($txc,$tyc,$tzc) = split( ' ', `mincstats -quiet -com -world_only $target` );
  my $dx = $txc - $sxc;
  my $dy = $tyc - $syc;
  my $dz = $tzc - $szc;
  $prev_xfm = "${tmpdir}/${s_base}_init.xfm";
  `param2xfm -clobber -translation $dx $dy $dz $prev_xfm`;
}

# a fitting we shall go...
for ($i=0; $i<=$#conf; $i++){

   # remove blurred image at previous iteration, if no longer needed.
   if( $i > 0 ) {
     if( $conf[$i]{blur_fwhm} != $conf[$i-1]{blur_fwhm} ) {
       unlink( "$tmp_source\_blur.mnc" ) if( -e "$tmp_source\_blur.mnc" );
       unlink( "$tmp_target\_blur.mnc" ) if( -e "$tmp_target\_blur.mnc" );
       unlink( "$tmp_source\_dxyz.mnc" ) if( -e "$tmp_source\_dxyz.mnc" );
       unlink( "$tmp_target\_dxyz.mnc" ) if( -e "$tmp_target\_dxyz.mnc" );
     }
   }
   
   # set up intermediate files
   $tmp_xfm = "$tmpdir/$s_base\_$i.xfm";
   $tmp_source = "$tmpdir/$s_base\_$conf[$i]{blur_fwhm}";
   $tmp_target = "$tmpdir/$t_base\_$conf[$i]{blur_fwhm}";
   
   print STDOUT "-+-------------------------[$i]-------------------------\n".
                " | steps:          @{$conf[$i]{steps}}\n".
                " | blur_fwhm:      $conf[$i]{blur_fwhm}\n".
                " | simplex:        $conf[$i]{simplex}\n".
                " | source:         $tmp_source\_$conf[$i]{type}.mnc\n".
                " | target:         $tmp_target\_$conf[$i]{type}.mnc\n".
                " | xfm:            $tmp_xfm\n".
                "-+-----------------------------------------------------\n".
                "\n";
   
   # blur the masked source and target images

   if(!-e "$tmp_source\_$conf[$i]{type}.mnc") {
     if( $conf[$i]{type} eq "dxyz" ) {
       # use unmasked image for gradients to avoid false gradient
       # at border of mask if mask is not so good
       &do_cmd('mincblur', '-clobber', '-no_apodize', '-fwhm', $conf[$i]{blur_fwhm},
               -gradient, $source, $tmp_source);
     } else {
       &do_cmd('mincblur', '-clobber', '-no_apodize', '-fwhm', $conf[$i]{blur_fwhm},
               $source_masked, $tmp_source);
     }
   }
   if(!-e "$tmp_target\_$conf[$i]{type}.mnc") {
     if( $conf[$i]{type} eq "dxyz" ) {
       # use unmasked image for gradients to avoid false gradient
       # at border of mask if mask is not so good
       &do_cmd('mincblur', '-clobber', '-no_apodize', '-fwhm', $conf[$i]{blur_fwhm},
               -gradient, $target, $tmp_target);
     } else {
       &do_cmd('mincblur', '-clobber', '-no_apodize', '-fwhm', $conf[$i]{blur_fwhm},
               $target_masked, $tmp_target);
     }
   }
   
   # set up registration
   @args = ('minctracc', '-clobber', $opt{objective},
            ( $i==0 ) ? '-lsq6' : 
            ( ( $i==1 && $opt{lsqtype} ne "-lsq6" ) ? '-lsq7' : $opt{lsqtype} ),
            '-step', @{$conf[$i]{steps}}, '-simplex', $conf[$i]{simplex},
            '-tol', $conf[$i]{tolerance});

   # If there is an initial transform, ignore the -est_translation.
   if( defined $prev_xfm ) {
     # Current transformation at this step
     push(@args, '-transformation', $prev_xfm ) 
   } else {
     # Initial transformation will be computed from the from Principal axis 
     # transformation (PAT).
     push(@args, @{$conf[$i]{trans}}) if( defined $conf[$i]{trans} );
   }

   # masks (even if the blurred image is masked, it's still preferable
   # to use the mask in minctracc)
   push(@args, '-source_mask', $opt{source_mask} ) if $i==$#conf && defined($opt{source_mask});
   push(@args, '-model_mask', $opt{target_mask}) if $i==$#conf && defined($opt{target_mask});
   
   # add files and run registration
   push(@args, "$tmp_source\_$conf[$i]{type}.mnc", "$tmp_target\_$conf[$i]{type}.mnc", 
        $tmp_xfm);
   &do_cmd(@args);

   # remove previous xfm to keep tmpdir usage to a minimum.
   # (not really necessary for a linear xfm - file is small.)
   if($i > 0) {
     unlink( $prev_xfm );
   }
   
   $prev_xfm = $tmp_xfm;
}

&do_cmd( 'mv', '-f', $prev_xfm, $outxfm );

# resample if required
if(defined($outfile)){
   print STDOUT "-+- creating $outfile using $outxfm\n".
   &do_cmd( 'mincresample', '-clobber', '-like', $target,
            '-transformation', $outxfm, $source, $outfile );
}


sub do_cmd { 
   print STDOUT "@_\n" if $opt{verbose};
   if(!$opt{fake}){
      system(@_) == 0 or die;
   }
}
       
