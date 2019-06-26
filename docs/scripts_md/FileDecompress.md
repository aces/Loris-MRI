# NAME

NeuroDB::FileDecompress -- Provides an interface to the file decompression of
LORIS-MRI

# SYNOPSIS

    use NeuroDB::FileDecompress;

    my $file_decompress = NeuroDB::FileDecompress->new($uploaded_file);

    my $extract = $file_decompress->Extract($decompressed_folder);

    my $archived_files = $file_decompress->getArchivedFiles($decompressed_folder);

    my $extract_directory = $file_decompress->getExtractedDirectory($decompressed_folder);

# DESCRIPTION

This library regroups utilities for manipulation of archived datasets.

## Methods

### new($file\_path) >> (constructor)

Create a new instance of this class.

INPUT: path of the file to extract.

RETURNS: an `Archive::Extract` object on success, or FALSE on failure

### Extract($destination\_folder)

This function will automatically detect the file-type and will decompress the
file by calling the appropriate function under the hood.

INPUT: full path to the destination folder

RETURNS: TRUE on success, FALSE on failure

### getArchivedFiles()

This function will return an array ref with the paths of all the files in the
archive.

RETURNS: array of archived files

### getExtractedDirectory()

This function will return the path to the directory where the files will be
extracted to.

RETURNS: path to the folder where file will be extracted

### getType()

This function will return the type of the archive

RETURNS: type of the archive

# COPYRIGHT AND LICENSE

License: GPLv3

# AUTHORS

LORIS community &lt;loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience
