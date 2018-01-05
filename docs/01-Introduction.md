# 1.0 - What is LORIS-MRI?  
LORIS-MRI is the backbone of the imaging component that makes up LORIS. 
These documents assume you have some
knowledge regarding LORIS and a functioning installation. For information
regarding LORIS itself, please consult the [LORIS wiki][1].

LORIS-MRI is responsible for the processing, visualizing, and archiving
of uploaded MRI scans. It expects an uploaded, compressed file containing
several [DICOM][2] files, processes this into [MINC][3] and [NII][4]
files, and then archives these files onto the server. Knowledge of
these file formats can be helpful, but are not necessary for using or
installing LORIS-MRI.

LORIS-MRI allows you to organize and archive your MRI data and links it with 
 corresponding behavioral data in LORIS.


[1]: https://github.com/aces/Loris/wiki 
[2]:http://dicomiseasy.blogspot.ca/2011/10/introduction-to-dicom-chapter-1.html
[3]: https://en.wikibooks.org/wiki/MINC/Introduction 
[4]:https://nifti.nimh.nih.gov/
