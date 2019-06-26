# NAME

mincpik - generate an image from a set of MINC volumes

# SYNOPSIS

mincpik \[options\] minc\_file \[outfile\]

# DESCRIPTION

This script generates an image from the MINC volumes found in the file passed on
the command line. Various scripts and external tools are used to accomplish this:
`mincinfo`, `mincreshape`, `mincextract`, `convert`, `rawtominc`, `montage `
and the open-source ImageMagick software (http://www.imagemagick.org). The list of 
options that affect the behaviour of `mincpik` is as follows:

- **-verbose** : be verbose
- **-clobber** : if it exists, overwrite the output file. An error is produced if `outfile` exists
and this option is not used.
- **-fake** : do not actually run the command but instead print on `STDOUT` all
the calls to the scripts and external tools (see above) issued to generate the image
- **-slice index** : `index` (starts at 0) of the slice to use to generate the image. Defaults to
`int(n/2)` (where `n` is the total number of slices) if not specified.
- **-scale scale** : scaling factor to use when generating the image. Defaults to 2. 
Note that this option is ignored if `-width` is used (see below)
- **-width width** : autoscale the image so it has a fixed width (in number of pixels). 
If this option is used, then the scaling factor (`-scale` option) is ignored.
- **-depth 8|16** : bit depth for resulting image (8 or 16). This option should
be used on big-endian machines only.
- **-title** : whether the image should be generated with a title or not
- **-title\_text title** : title text for the generated image
- **-title\_size size** : font size (in pt.) to use when generating the image title
- **-anot\_bar text** : use the supplied text argument as the annotation bar for the image.
Note that the image height will be used to determine the bar size.
- **-lookup -hotmetal|-gray|-grey|-spectral**: use the specified lookup table to compute RGB
values when generating the images (see the manpage for `minclookup`).
- **-range min max** : specifies  the  range  of voxel values to consider, in their
integer representation. Default is the full range for the type and sign. 
This option is ignored for floating point values. See manpage for `mincreshape`.
- **-image\_range min max** : Normalize the image to a given `min` and `max` real value (not
voxel value). Cannot be used with `-auto_range`. See manpage for `mincreshape`.
- **-auto\_range** : Automatically find the range used to normalize the image. This is
done by finding the 5% to 95% PcT image range using `mincstats`. This option
cannot be used with `-image_range`. If not specified (and if `-image_range` is not specified) 
then the entire image (range = 0-100) is used.
- **-transverse** : add the transverse slices to the set of slices to consider during
image generation. The transverse slices are always considered during image generation 
so this option is useless/obsolete 
- **-coronal** : add the coronal slices to the set of slices to consider during image generation
- **-sagittal** : add the sagittal slices to the set of slices to consider during image generation
- **-axial** : same as transverse
- **-allthree** : deprecated. Use `-triplanar` instead.
- **-triplanar** : use slices in all dimensions to generate the image. Same as specifying
`'-axial -coronal -sagittal'`
- **-tilesize size** : the size in pixel of each image when `-triplanar` is used.
- **-sagittal\_offset offset** : Offset the sagittal slices by `offset`. For example:

    `./mincpik -slice 15 -sagittal -sagittal_offset 3 in.mnc out.png`

    would generate an image using slice at index 18 (15+3). Cannot be used 
    with `-sagittal_offset_perc` (see below)

- **-sagittal\_offset\_perc perc** : same as `-sagittal_offset` but with an offset given as
a percentage of the total number of slices in the sagittal dimension. Note that
`perc` should be a number between 0 and 100. This option cannot be used in conjunction
with `-sagittal_offset`
- **-vertical** : when generating triplanar images, put the image associated to each dimension
stacked in a vertical row. This is the default behaviour when `-triplanar` is used.
- **-horizontal** : when generating triplanar images, put the image associated to each
dimension stacked in a horizontal row.

The `outfile` command line argument is optional. If not specified, output will be a PNG image
written to STDOUT. If `outfile` is specified, the file extension will determine the type of
the generated image (`.jpg` for JPEG images, `.gif` for GIF images, etc...)

# LICENSING

License: GPLv3

# AUTHORS

Andrew Janke - a.janke@gmail.com,
LORIS community &lt;loris.info@mcin.ca> and McGill Centre for Integrative
Neuroscience
