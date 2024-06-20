package NeuroDB::Utilities;

=pod

=head1 NAME

NeuroDB::Utilities -- A set of utility functions to perform common tasks

=head1 SYNOPSIS

 use NeuroDB::Utilities;

 my $blake2b = blake2b_hash('path_to_file.txt');

 ...

=head1 DESCRIPTION

A mishmash of utility functions, primarily used for MINC file manipulations.

=head2 Methods

=cut

use strict;
use warnings;

use Digest::BLAKE2 qw(blake2b);


=pod

=head3 blake2b_hash($filepath)

Computes blake2b hash of a file and returns the blake2b hash.

INPUTS:
  - $filepath: path of the file to run blake2b hashing on

RETURNS: blake2b hash of the file.

=cut

sub blake2b_hash {
    my ($filepath) = @_;

    open(FILE, $filepath) or die "Can't open '$filepath': $!";
    binmode(FILE);

    return Digest::BLAKE2->new->addfile(*FILE)->hexdigest;
}

1;

