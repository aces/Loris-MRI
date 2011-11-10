#!/usr/bin/perl

use strict;
use Data::Dumper;

my $profile = "artProd";
my $pipelineLabel = 'Civet-1-1-8-MF-196';
my $prefix  = "art";
my $regCMD = "./registerFile.pl -profile $profile";

my $path   = "/export-01/art/mri-data/processing/art-V1-Civet-1.1.8";
my @ids = `ls -1 $path/ | cut -d '_' -f 2`;

#print Dumper(@ids);

my ($final, $classify, $artefact, $bmask, $smask, $nmask, $nl);
my $c = 0;
my $real = 1;


foreach my $i (@ids) {
    $c++;
    if ($c > 100) { exit; }
    chomp($i);
    print "Inserting data for $i\n";
    $final = "$regCMD $path/${i}/final/${prefix}_${i}_t1_final.mnc linreg -coordspace linear -protocol t1 -pipeline $pipelineLabel -profile $profile";
    my $idgiven = `$final | grep FileID | cut -d ':' -f 2` if $real;
    $nl    = "$regCMD $path/${i}/final/${prefix}_${i}_t1_nl.mnc nlreg -coordspace nonlinear -protocol t1 -pipeline $pipelineLabel -profile $profile";

    chomp($idgiven);
    $classify = "$regCMD $path/${i}/classify/${prefix}_${i}_classify.mnc classify  -coord linear -protocol clean_cls -pipeline $pipelineLabel -classifyalg clean -source $idgiven" if $real;
    $artefact = "$regCMD $path/${i}/classify/${prefix}_${i}_artefact.mnc artefact  -coord linear -protocol artefact_mask -pipeline $pipelineLabel -source $idgiven";

    $nmask = "$regCMD $path/${i}/mask/${prefix}_${i}_skull_mask_native.mnc native -coord native -pipeline $pipelineLabel -protocol native_mask -source $idgiven"; 
    $bmask = "$regCMD $path/${i}/mask/${prefix}_${i}_brain_mask.mnc brainmask -coord linear -pipeline $pipelineLabel -protocol tal_mask -source $idgiven";
#    $smask = "$regCMD $path/${i}/mask/${prefix}_${i}_skull_mask.mnc skullmask -coord linear -pipeline $pipelineLabel -protocol tal_msk -source $idgiven";
#    $animal = "$regCMD $path/${i}/segment/${prefix}_${i}_stx_labels.mnc animal -coord nonlinear   -pipeline $pipelineLabel             -source $idgiven";
    
    print "\n $classify\n $bmask\n $smask\n $artefact";
    
    if ($idgiven) {
        
        `$classify` if $real;
        `$artefact` if $real;
        `$bmask` if $real;
        `$nmask` if $real;
        `$nl` if $real;
    #    `$animal` if $real;
    #    `$smask` if $real;
    }
}
