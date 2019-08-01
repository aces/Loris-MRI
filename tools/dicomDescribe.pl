#!/usr/bin/perl

=pod

=head1 NAME

dicomDescribe.pl -- a script to see DICOM header information


=head1 SYNOPSIS

perl tools/dicomDescribe.pl C<[/path/to/DICOM/file]>


=head1 DESCRIPTION

This script takes a DICOM file as an argument, parses it using the
C<DICOM::DICOM> library and prints the content of the DICOM header in the
terminal.

=head1 LICENSING

License: GPLv3

=head1 AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative
Neuroscience

=cut


use DICOM::DICOM;

$dicom = DICOM->new();

$dicom->fill($ARGV[0]);
$dicom->printContents();


