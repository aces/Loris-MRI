import argparse
import textwrap
import sys, getopt  # For script options
import os           # Operating System library to create directories and files
import errno        # For python 2.7 compatibility
import getpass      # For input prompt not to show what is entered
import json         # Provide convenient functions to handle JSON objects 
import requests     # To handle HTTP requests

import warnings
warnings.simplefilter('ignore') # Because I am using unverified ssl certificates 

parser = argparse.ArgumentParser(
    formatter_class=argparse.RawDescriptionHelpFormatter,
    description=textwrap.dedent("""\
This script runs the Loris-MRI insertion pipeline on multiple scans. The list of
scans are provided through a text file (e.g. C<list_of_scans.txt>) with one scan
details per line.

The scan details includes the path to the scan, identification as to whether the
scan is for a phantom (Y) or not (N), and the candidate name. As opposed to the
perl script, this one always requires a patient_name, even for non-phantom entries.

Like the LORIS Imaging Uploader interface, this script also validates the
candidate's name against the (start of the) filename and creates an entry in the
C<mri_upload> table.

An example of what C<list_of_scans.txt> might contain for 3 uploads to be
inserted:

 /data/incoming/PSC0001_123457_V1.tar.gz N PSC0000_123456_V1
 /data/incoming/lego_Phantom_MNI_20140101.zip Y
 /data/incoming/PSC0001_123457_V1_RES.tar.gz N PSC0000_123456_V1

To start the mri_upload process on the LORIS server for each file, use the 
autostart (-a) option when calling this script.

"""
))

parser.add_argument('-b', '--baseurl', required=True, help='LORIS API url with version.')
parser.add_argument('-i', '--inputfile', required=True, help='The list of scans.')
parser.add_argument('-a', '--autostart', action='store_const', const=True, help='If present, will attempt to start the mri_upload process for each scans.')

args = parser.parse_args()

def prettyPrint(string):
    print(json.dumps(string, indent=2, sort_keys=True))

def dicomUpload(filepath, isphantom, patientname):
    pscid, candid, visit_label = patientname
    filename = os.path.basename(filepath)
    files = {'mriFile': (filename, open(filepath, "rb"), 'application/x-tar')}
    payload = {
        'IsPhantom': 'true' if isphantom == 'Y' else 'false',
        'CandID': candid,
        'PSCID': pscid,
        'Visit': visit_label
    }
    response = requests.post(
        url = args.baseurl + '/candidates/' + candid + '/' + visit_label + '/dicoms/',
        headers = {'Authorization': 'Bearer %s' % jwtoken, 'LORIS-Overwrite': 'overwrite'},
        verify = False,
        data = payload,
        files = files
    )
    responsebody = response.content.decode('ascii')
    if (response.status_code != 200):
        raise ValueError(responsebody)
    
    
    data = json.loads(responsebody)
    return data['mri_uploads'].pop()['mri_upload_id']

def startProcess(filename, patientname, mri_upload_id):
    pscid, candid, visit_label = patientname
    payload = {
        'ProcessType': 'mri_upload',
        'MRIUploadID': mri_upload_id
    }
    response = requests.post(
        url = args.baseurl + '/candidates/' + candid + '/' + visit_label + '/dicoms/' + filename + '/processes',
        headers = {'Authorization': 'Bearer %s' % jwtoken},
        verify = False,
        data = payload
    )
    if (response.status_code != 202):
        raise ValueError(responsebody)
        
    return json.loads(response.content.decode('ascii'))

if __name__ == '__main__':
    
    credentials = {
        'username': input('LORIS username: '), 
        'password': getpass.getpass('password: ')
    }
    
    jwtoken = json.loads(requests.post(
        url = args.baseurl + '/login',
        json = credentials,
        verify = False
    ).content.decode('ascii'))['token']
    
    for line in open(args.inputfile):
        if (len(line) == 0):
           continue 

        params      = line.split(' ')
        if (len(params) != 3):
            print('Invalid line: ' + line)
            sys.exit(1)
        filepath    = params[0]
        isphantom   = params[1]
        patientname = params[2].strip()
        
        try:
            open(filepath, 'rb')
        except FileNotFoundError as err:
            print('Skipping ' + filepath)
            print(err.args)
            continue
        
        print('Uploading ' + filepath)
        try:
            mri_upload_id = dicomUpload(filepath, isphantom, patientname.split('_',2))
        except ValueError as err:
            print('Upload failed')
            print(err.args[0])
            continue
            
        print('Upload succesfull')
        print('mri_upload_id: ' + str(mri_upload_id))
        
        if (args.autostart):
            try:
                responsebody = startProcess(os.path.basename(filepath), patientname.split('_',2), mri_upload_id)
            except ValueError as err:
                print('Upload failed')
                print(err.args[0])
                continue
                
            print('mri_upload process started')
            prettyPrint(responsebody)
            print('***************************')
            print('')

