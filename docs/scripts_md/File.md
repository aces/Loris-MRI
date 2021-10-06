# NAME

NeuroDB::File -- Provides an interface to the MRI file management subsystem of
LORIS

# SYNOPSIS

    use NeuroDB::File;
    use NeuroDB::DBI;

    my $dbh = NeuroDB::DBI::connect_to_db();

    my $file = NeuroDB::File->new(\$dbh);

    my $fileID = $file->findFile('/path/to/some/file');
    $file->loadFile($fileID);

    my $acquisition_date = $file->getParameter('acquisition_date');
    my $parameters_hashref = $file->getParameters();

    my $coordinate_space = $file->getFileDatum('CoordinateSpace');
    my $filedata_hashref = $file->getFileData();


    # less common to use methods, available mainly for register_db...
    my $dbh_copy = $file->getDatabaseHandleRef();

    $file->loadFileFromDisk('/path/to/some/file');
    $file->setFileData('CoordinateSpace', 'nonlinear');
    $file->setParameter('patient_name', 'Larry Wall');

    my $parameterTypeID = $file->getParameterTypeID('patient_name');

# DESCRIPTION

This class defines a MRI (or related) file (minc, bicobj, xfm,
etc) as represented within the LORIS database system.

**Note:** if a developer does something naughty (such as leaving out
the database handle ref when instantiating a new object or so on) the
class will croak.

## Methods

### new(\\$dbh) >> (constructor)

Create a new instance of this class. The parameter `\$dbh` is a
reference to a DBI database handle, used to set the object's database
handle, so that all the DB-driven methods will work.

INPUT: DBI database handle.

RETURNS: new instance of this class.

### loadFile($fileID)

Load the object with all the data pertaining to a file as defined by
parameter `$fileID`.

INPUT: ID of the file to load.

RETURNS: 0 if no file was found, 1 otherwise.

### findFile($filename)

Finds the `FileID` pertaining to a file as defined by parameter `$filename`,
which is a full `/path/to/file`.

INPUT: full path to the file to look for an ID in the database.

RETURNS: (int) FileID or undef if no file was found.

### getFileData()

Gets the set of file data (data from the `files` table in the database).

RETURNS: hashref of the contents of the record in the `files` table for the
loaded file.

### getFileDatum($datumName)

Gets one element from the file data (data from the `files` table in the
database).

INPUT: name of the element to get.

RETURNS: scalar of the particular datum requested pertaining to the loaded file.

### getParameter($parameterName)

Gets one element from the file's parameters (data from the `parameter_file`
table in the database).

INPUT: name of the element from the file's parameter

RETURNS: scalar of the particular parameter requested pertaining to the loaded
file.

### getParameters()

Gets the set of parameters for the loaded file (data from the `parameter_file`
table in the database).

RETURNS: hashref of the records in the `parameter_file` table for the loaded
file.

### getDatabaseHandleRef()

Gets the database handle reference which the object is using internally.

RETURNS: DBI database handle reference.

### getFileType($file)

Determines the imaging file type based on the extension of the file to insert
and the list of available types in the `ImagingFileTypes` table of the
database.

INPUT: the path to the imaging file to determine the file type

RETURNS: the type of the imaging file given as an argument

### loadFileFromDisk($filename)

Reads the headers from the file specified by `$filename` and loads the current
object with the resultant parameters.

INPUT: file to read the headers from.

RETURNS: 0 if any failure occurred or 1 otherwise.

### setFileData($propertyName, $value)

Sets the fileData property named `$propertyName` to the value of `$value`.

INPUTS:
  - $paramName: name of the `fileData` property
  - $value    : value of the `fileData` property to be set

### setParameter($parameterName, $value)

Sets the parameter named `$parameterName` to the value of `$value`.

INPUTS:
  - $paramName: name of the parameter
  - $value    : value of the parameter to be set

### removeParameter($parameterName)

Removes the parameter named `$parameterName`.

INPUT: name of the parameter to remove

### getParameterTypeID($parameter)

Gets the `ParameterTypeID` for the parameter `$parameter`.  If `$parameter`
does not exist, it will be created.

INPUT: name of the parameter type

RETURNS: `ParameterTypeID` (int)

### removeWhitespace($value)

Removes white space from variable `$value`.

INPUT: variable to remove white space from (string or array)

RETURNS: string or array of the value without white spaces

### filterParameters

Manipulates the NeuroDB::File object's parameters and removes all parameters of
length > $MAX\_DICOM\_PARAMETER\_LENGTH

# TO DO

Other operations should be added: perhaps `get*` methods for those fields in
the `files` table which are lookup fields.

Fix comments written as #fixme in the code.

# COPYRIGHT AND LICENSE

Copyright (c) 2004,2005 by Jonathan Harlap, McConnell Brain Imaging Centre,
Montreal Neurological Institute, McGill University.

License: GPLv3

# AUTHORS

Jonathan Harlap <jharlap@bic.mni.mcgill.ca>,
LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative Neuroscience
