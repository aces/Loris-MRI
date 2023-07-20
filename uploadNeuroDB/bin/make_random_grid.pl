#!/usr/bin/env perl

### CECILE MADJAR - MODIFIED THIS SCRIPT FROM THE ORIGINAL INSTALL TO
###                 BE USING `mincblur` instead of `fast_blur` WHICH
###                 FAILED RUNNING ON PHASE 2 RELEASE OF OPEN PREVENT-AD

############################# MNI Header #####################################
#@NAME       :  make_random_grid.pl
#@DESCRIPTION:  produce pseudo-random deformation grid
#@COPYRIGHT  :
#              Vladimir S. Fonov  February, 2009
#              Montreal Neurological Institute, McGill University.
#              Permission to use, copy, modify, and distribute this
#              software and its documentation for any purpose and without
#              fee is hereby granted, provided that the above copyright
#              notice appear in all copies.  The author and McGill University
#              make no representations about the suitability of this
#              software for any purpose.  It is provided "as is" without
#              express or implied warranty.
###############################################################################


use strict;
use File::Basename;
use File::Temp qw/ tempfile tempdir /;
use Getopt::Long;

my $fake=0;
my $verbose=0;
my $clobber=0;
my $amp=1.0;
my $fwhm=10;
my $me=basename($0);
my $keep_tmp=0;
my $mask;
my $byte;
my $edge_smooth;

GetOptions (    
  "verbose"       => \$verbose,
  "clobber"       => \$clobber,
  "amplitude=f"   => \$amp,
  "fwhm=f"        => \$fwhm,
  "keep_tmp"      => \$keep_tmp,
  "mask=s"        => \$mask,
  "byte"          => \$byte,
  "edge_smooth=f" => \$edge_smooth
); 

die <<HELP
Usage: $me <sample> <output_grid> 
 [--verbose
  --clobber
  --amplitude <f>
  --mask <mask>
  --edge_smooth <f>
  --fwhm <f> ]
HELP
if $#ARGV<1;

my ($sample,$out)=@ARGV;

check_file($out) unless $clobber;

my $tmpdir = &tempdir( "$me-XXXXXXXX", TMPDIR => 1, CLEANUP => !$keep_tmp );

my $iter;
my @files;
my $tmp_mask;

if($mask)
{
  do_cmd('mincresample',$mask,'-like',$sample,'-nearest',"$tmpdir/mask.mnc");
}

if($edge_smooth && $mask)
{
  
  my $step=`mincinfo -attvalue xspace:step $tmpdir/mask.mnc`;
  chomp($step);
  $step*=$edge_smooth;
  do_cmd('itk_morph','--exp',"E[${edge_smooth}]","$tmpdir/mask.mnc","$tmpdir/mask.mnc",'--clobber'); #itk_morph can overwrite input
  do_cmd('mincblur','-fwhm',$step,"$tmpdir/mask.mnc","$tmpdir/mask");
  do_cmd('minccalc','-express','clamp(A[0],0,1)',"$tmpdir/mask_blur.mnc","$tmpdir/smooth.mnc");
}

for($iter=0;$iter<3;$iter++){
  do_cmd('random_volume',$sample,"${tmpdir}/${iter}.mnc",'--float');
  do_cmd('mincblur','-fwhm',$fwhm, "${tmpdir}/${iter}.mnc", "${tmpdir}/${iter}");
  if($mask) 
  {
    do_cmd('mincresample','-nearest',"${tmpdir}/${iter}_blur.mnc","${tmpdir}/${iter}_blur_.mnc",'-like',$mask);
    do_cmd('mv',"${tmpdir}/${iter}_blur_.mnc","${tmpdir}/${iter}_blur.mnc");
  }
  my ($min,$max)=split(/\n/,`mincstats -q -min -max  ${tmpdir}/${iter}_blur.mnc`);
  my $k=$amp*2.0/($max-$min);
  my @args=('minccalc','-clobber',"${tmpdir}/${iter}_blur.mnc",'-expression');
  if($mask) {
    push @args,"A[0]*$k*A[1]";
    if($edge_smooth)
    {
      push @args,"$tmpdir/smooth.mnc","${tmpdir}/${iter}.mnc";
    } else {
      push @args,"$tmpdir/mask.mnc","${tmpdir}/${iter}.mnc";
    }
  } else {
    push @args,"A[0]*$k","${tmpdir}/${iter}.mnc";
  }
  push @args,'-byte' if $byte;
  do_cmd(@args);
  push(@files,"${tmpdir}/${iter}.mnc");
}

do_cmd('mincconcat', '-clobber', '-concat_dimension', 'vector_dimension', '-coordlist',"0,1,2", @files, $out);

sub do_cmd {
    print STDOUT "@_\n" if $verbose;
    if(!$fake) {
        system(@_) == 0 or die "DIED: @_\n";
    }
}
sub check_file {
  die("${_[0]} exists!\n") if -e $_[0];
}

