package NeuroDB::FileDecompress;

=pod

=head1 NAME

NeuroDB::FileDecompress -- Provides an interface to the file decompression of
LORIS-MRI

=head1 SYNOPSIS

  use NeuroDB::FileDecompress;

  my $file_decompress = NeuroDB::FileDecompress->new($uploaded_file);

  my $extract = $file_decompress->Extract($decompressed_folder);

  my $archived_files = $file_decompress->getArchivedFiles($decompressed_folder);

  my $extract_directory = $file_decompress->getExtractedDirectory($decompressed_folder);

=head1 DESCRIPTION

This library regroups utilities for manipulation of archived datasets.

=head2 Methods

=cut

use English;
use Carp;
use strict;
use warnings;
use Data::Dumper;
use Path::Class;
use Archive::Extract;
use Archive::Zip;


=pod

=head3 new($file_path) >> (constructor)

Create a new instance of this class.

INPUT: path of the file to extract.

RETURNS: an C<Archive::Extract> object on success, or FALSE on failure

=cut

sub new {
    my $params = shift;
    my ($file_path) = @_;
    my $self = {};
    my $extract_object = Archive::Extract->new( 
            archive => $file_path 
            );
    $self->{'extract_object'} = $extract_object;
    return bless $self, $params;
}


=pod

=head3 Extract($destination_folder)

This function will automatically detect the file-type and will decompress the
file by calling the appropriate function under the hood.

INPUT: full path to the destination folder

RETURNS: TRUE on success, FALSE on failure

=cut

sub Extract  {
    my $this = shift;
    my ($destination_folder) = @_;

    # Check to see if the destination folder exists
    return $this->{'extract_object'}->extract(to=>$destination_folder);
}


=pod

=head3 getArchivedFiles()

This function will return an array ref with the paths of all the files in the
archive.

RETURNS: array of archived files

=cut

sub getArchivedFiles {
    my $this = shift;
    return  $this->{'extract_object'}->files;
}


=pod

=head3 getExtractedDirectory()

This function will return the path to the directory where the files will be
extracted to.

RETURNS: path to the folder where file will be extracted

=cut

sub getExtractedDirectory {
    my $this = shift;
    return $this->{'extract_object'}->extract_path();
}


=pod

=head3 getType()

This function will return the type of the archive

RETURNS: type of the archive

=cut


sub getType {
    my $this = shift;
    return  $this->{'extract_object'}->type;
}
1; 


=pod

=head1 COPYRIGHT AND LICENSE

License: GPLv3

=head1 AUTHORS

LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience

=cut