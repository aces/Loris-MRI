BACKPOPULATESNRANDACQUIUSsIeTrIOCNoOnRtDrEiRb(u1t)ed PerBlACDKoPcOuPmUeLnAtTaEtSiNoRnANDACQUISITIONORDER(1)



NNAAMMEE
       BackPopulateSNRAndAcquisitionOrder.pl -- a script that back populates
       the AcqOrderPerModality column of the files table, and the
       signal-to-noise ratio (SNR) values in the parameter_file table for
       inserted MINC files. The SNR is computed using MINC tools built-in
       algorithms.

SSYYNNOOPPSSIISS
       perl tools/BackPopulateSNRAndAcquisitionOrder.pl "[options]"

       Available options are:

       -profile        : name of the config file in
                         "../dicom-archive/.loris_mri"

       -tarchive_id    : The tarchive ID of the DICOM archive (.tar files) to
       be
                         processed from the "tarchive" table

DDEESSCCRRIIPPTTIIOONN
       This script will back populate the files table with entries for the
       AcqOrderPerModality column; in reference to:
       https://github.com/aces/Loris-MRI/pull/160 as well as populate the
       parameter_file table with SNR entries in reference to:
       https://github.com/aces/Loris-MRI/pull/142 It can take in tarchiveID as
       an argument if only a specific DICOM archive (.tar files) is to be
       processed; otherwise, all DICOM archives (.tar files) in the "tarchive"
       table are processed.

TTOO DDOO
       Nothing planned.

BBUUGGSS
       None reported.

LLIICCEENNSSIINNGG
       License: GPLv3

AAUUTTHHOORRSS
       LORIS community <loris.info@mcin.ca> and McGill Centre for Integrative
       Neuroscience



perl v5.18.2                      2018-01-B1A7CKPOPULATESNRANDACQUISITIONORDER(1)
