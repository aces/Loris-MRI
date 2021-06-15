#!/usr/bin/perl -w

=pod

=head1 NAME

replicate_raisinbread_for_mcin_dev_vm.pl -- Create a local copy of the RaisinBread dataset and
store each file as a symlink to the original dataset found in /data-raisinbread automatically mounted
with all LORIS dev VMs created by MCIN. 

=head1 SYNOPSIS

perl replicate_raisinbread_for_mcin_dev_vm.pl C<[/path/to/mounted/raisinbread]> C<[/path/to/output_dir]> 

=head1 DESCRIPTION

This script takes in two arguments. The first argument is the path to the
RaisinBread dataset (typically C</data-raisinbread>) and the path to the
directory where the replicated dataset will be stored. For example, suppose
the script is run with the following arguments:

perl replicate_raisinbread_for_mcin_dev_vm.pl C</data-raisinbread> C</data>

The replicated dataset will be found in C</data/data-raisinbread/> 

=head1 LICENSING

License: GPLv3

=head1 AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

=cut

use strict;
use warnings;
use NeuroDB::ExitCodes;

use Cwd qw/abs_path/;
use File::Find;
use File::Spec::Functions qw/catfile abs2rel/;
use File::Path qw/make_path/;

my $Usage = <<USAGE;
usage:  $0 /path/to/raisinbread /path/to/output_dir

This script creates a local copy of the RaisinBread dataset and stores each file 
as a symlink to the original dataset.

This script takes in two arguments. The first argument is the path to the
RaisinBread dataset (typically /data-raisinbread) and the path to the
directory where the replicated dataset will be stored. For example, suppose
the script is run with the following arguments:

perl replicate_raisinbread_for_mcin_dev_vm.pl /data-raisinbread /data/data-raisinbread/

The replicated dataset will be found in /data/data-raisinbread/

USAGE

# Checks if the right number of arguments are given
if (scalar(@ARGV) != 2) {
    print STDERR "ERROR: Incorrect number of arguments\n";
    print $Usage;
    exit $NeuroDB::ExitCodes::MISSING_ARG;
}

# Get the path of RaisinBread dataset and the directory where the copy dataset 
# will be stored
my $rb_dir      = abs_path($ARGV[0]);
my $output_dir  = abs_path($ARGV[1]);   

# find() traverses the RaisinBread directory tree in-order. For each sub-
# directory or file found, it calls the &wanted subroutine
find(\&wanted, $rb_dir);
   
sub wanted {
    # Get the relative path of the file/directory (relative to $rb_dir)
    my $relative_path = abs2rel($File::Find::name, $rb_dir);

    # Join the output directory path and the relative path determined above.
    my $out_path = catfile($output_dir, $relative_path);

    # If it's a file, create a symlink. Else, it's a directory, so create it.
    if (-f $File::Find::name) {
        symlink($File::Find::name, $out_path);
    } else {
        make_path($out_path);
    }   
}
