#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin";
use DICOM::DICOM;
$dicom = DICOM->new();

$dicom->fill($ARGV[0]);
$dicom->printContents();


