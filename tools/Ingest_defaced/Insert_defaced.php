<?php

/**
 * This script processes all BIDS scans in a given directory and all its sub-directries
 * and does the following:
 *
 * 1. Inserts in table files the anonymized version of this scan.
 * 2. Inserts in table parameter_file the parameters for the anonymized scan created in
 *    steps 1 (this includes the anonymized JSON sidecar).
 * 3. Creates the anonymized scan file and JSON sidecar file under directory assembly_bids.
 * 4. Creates an association between the anonymized and non-anonymized scan in table
 *    files_intermediary.
 */
require_once __DIR__ . '/../../../tools/generic_includes.php';
require_once __DIR__ . '/../../../modules/imaging_browser/php/viewsession.class.inc';

//--------------------------------------------------------------------//
// All BIDS/JSON file combos under this directory will be processed   //
//--------------------------------------------------------------------//
const DEFACED_SCANS_ROOT_DIR = '/data/external/bic/capture-defaced/to_anonymize_and_insert/';
//const DEFACED_SCANS_ROOT_DIR = '/cbigr_prod_ro/external/bic/capture-defaced/to_anonymize_and_insert/';

//---------------------------------//
// Project these scans belong to   //
//---------------------------------//
const PROJECT = 'CaptureALS';

//--------------------------------------------------//
// Parameter to scrub in table table parameter_file //
//--------------------------------------------------//
const SCAN_PARAMETERS_TO_SCRUB = [
    'acquisition_time',
    'patient:weight',
    'patient_name',
    'series_instance_uid',
    'patient_id',
    'institution_name',
    'time',
    'InstitutionalDepartmentName',
    'InstitutionAddress',
    'ProcedureStepDescription',
    'PatientBirthDate',
    'PatientSex',
    'AcquisitionDateTime',
    'ReferringPhysicianName'
];

//--------------------------------------------//
// Values to scrub in the scan's JSON sidecar //
//--------------------------------------------//
const JSON_HEADERS_TO_SCRUB = [
    'AcquisitionTime',
    'PatientWeight',
    'PatientName',
    'SeriesInstanceUID',
    'PatientID',
    'InstitutionName',
    'InstitutionalDepartmentName',
    'InstitutionAddress',
    'ProcedureStepDescription',
    'PatientBirthDate',
    'PatientSex',
    'AcquisitionDateTime',
    'StudyInstanceUID'
];

//-----------------------------------------------//
// Scrubbed values are replaced with this string //
//-----------------------------------------------//
const SCRUBBED_PARAMETER_VALUE = '__SCRUBBED__';

//--------------------------------------------------------------//
// Set to true if you don't want to modify the DB or the file   //
// system.                                                      //
//--------------------------------------------------------------//
$dryRun = false;

//----------------------------------------------------------//
// Find all BIDS and JSON files in DEFACED_SCANS_ROOT_DIR   //
//----------------------------------------------------------//
$niiFilePaths  = glob(DEFACED_SCANS_ROOT_DIR . '*/*/*/*.nii.gz');
$jsonFilePaths = glob(DEFACED_SCANS_ROOT_DIR . '*/*/*/*.json');

printf("Script started on %s.\n", date("Y-m-d h:i:s a"));

//-------------------------------------------------------//
// Get all CAPT BIDS & JSON files stored in the database //
//-------------------------------------------------------//
$query = "
    SELECT f.File, f.FileID, pf_bids_json.Value as jsonFilePath, f.SessionID, s.CandID
    FROM files f
    JOIN session s ON (s.ID=f.sessionid)
    JOIN Project P ON (P.projectid=s.projectid AND P.Name=:project)
    LEFT JOIN (
        SELECT pf2.FileID,pf2.value
        FROM parameter_file pf2
        WHERE ParameterTypeID = (
            SELECT ParameterTypeID
            FROM parameter_type
            WHERE Name='bids_json_file'
        )
    ) pf_bids_json ON (pf_bids_json.FileID=f.fileid)
";
$rows = $DB->pselect($query, ['project' => PROJECT]);

foreach ($rows as $row) {
    $bidsScans[basename($row['File'])] = $row;
}

//---------------------------------------//
// Get all CAPT sessions in the database //
//---------------------------------------//
$query = "
    SELECT s.*
    FROM session s
    JOIN Project P ON (P.projectid=s.projectid AND P.Name=:project)
";
$sessions = $DB->pselectWithIndexKey($query, ['project' => PROJECT], 'ID');

//------------------------------------//
// Get all visit_label in table visit //
//------------------------------------//
$query = "
    SELECT VisitLabel FROM visit
";
$rows = $DB->pselect($query, []);
foreach ($rows as $row) {
    $visitLabels[] = $row['VisitLabel'];
}

//--------------------------------------------------------//
// Process each BIDS file found in DEFACED_SCANS_ROOT_DIR //
//--------------------------------------------------------//
foreach ($niiFilePaths as $niiFilePath) {
    //------------------------------------------------------------------------------//
    // First, check if there's a correpsonding JSON file in DEFACED_SCANS_ROOT_DIR  //
    //------------------------------------------------------------------------------//
    $jsonFilePathInDefacedDir = preg_replace('/.nii.gz$/', '.json', $niiFilePath);
    if (!file_exists($jsonFilePathInDefacedDir)) {
        fwrite(STDERR, "File $niiFilePath does not have a corresponding JSON file. Skipped.\n");
        continue;
    }

    $niiScanBasename = basename($niiFilePath);

    if (!isset($bidsScans[$niiScanBasename])) {
        fwrite(STDERR, "Scan $niiScanBasename not found in DB. Skipping.\n");
        continue;
    }
    if (empty($bidsScans[$niiScanBasename]['jsonFilePath'])) {
        fwrite(STDERR, "Scan $niiScanBasename does not have an associated JSON in DB. Skipping.\n");
        continue;
    }

    $sessionID             = $bidsScans[$niiScanBasename]['SessionID'];
    $visitLabel            = $sessions[$sessionID]['Visit_label'];
    $anonSessionVisitLabel = "{$visitLabel}Anonymized";

    // This is the path of the JSON sidecar found in the parameter_file table
    $jsonFilePath        = $bidsScans[$niiScanBasename]['jsonFilePath'];

    // These are the paths of the anonymized scan and associated JSON sidecar will have
    $anonJsonFilePath = preg_replace('/(_run\d+_)/', '{$1}desc-defaced_', $jsonFilePath);
    $anonJsonFilePath = preg_replace("/$visitLabel/", $anonSessionVisitLabel, $anonJsonFilePath);

    $anonNiiFilePath = preg_replace('/(_run\d+_)/', '{$1}desc-defaced_', $bidsScans[$niiScanBasename]['File']);
    $anonNiiFilePath = preg_replace("/$visitLabel/", $anonSessionVisitLabel, $anonNiiFilePath);

    if(array_key_exists(basename($anonNiiFilePath), $bidsScans)) {
        printf("Defaced scan %s has already been inserted in the database. Skipped.\n", basename($anonNiiFilePath));
        continue;

        // TODO:
        // If the defaced scan already exists, it should not be skipped. Instead, the defaced
        // scan should be UPDATED along with the associated records in the DB (don't forget the
        // md5sum).
    }

    //--------------------------------------------------//
    // Create anonymized session if it does not exist   //
    //--------------------------------------------------//
    $anonSessionID = createSessionIfNeeded($bidsScans[$niiScanBasename], $anonSessionVisitLabel, $sessions, $visitLabels);

    //---------------------------------------------------------//
    // Insert anonymized file in table files and tie it to the //
    // session created above                                   //
    //---------------------------------------------------------//
    $anonScanID = insertAnonScanInDB(
        $anonSessionID, $bidsScans[$niiScanBasename]['FileID'], $anonNiiFilePath, $anonJsonFilePath
    );

    //------------------------------------------------------//
    // Get content of JSON file associated to the BIDS scan //
    // and scrub the headers that contain PII.              //
    //------------------------------------------------------//
    $scrubbedJsonData = getScrubbedJsonData($jsonFilePathInDefacedDir);

    //--------------------------------------------------------------------------------//
    // Put the anonymized BIDS file and associated anonymized JSON in the appropriate //
    // directory on the file system.                                                  //
    //--------------------------------------------------------------------------------//
    createAnonJsonAndNii($bidsScans[$niiScanBasename]['File'], $niiFilePath, $anonNiiFilePath, $anonJsonFilePath, $scrubbedJsonData);

    //-------------------------------------------------------------------------------//
    // Associate anonymized file to non-anonymized file in table files_intermediary  //
    //-------------------------------------------------------------------------------//
    if (!$dryRun) {
        $DB->insert(
            'files_intermediary',
            [
                'Output_FileID'  => $anonScanID,
                'Input_FileID'   => $bidsScans[$niiScanBasename]['FileID'],
                'Tool'           => 'defacing'
            ]
        );
    }
    print "Added association between files $anonScanID and {$bidsScans[$niiScanBasename]['FileID']} in files_intermediary.\n";
    print "===============================================================================================================\n";
}

printf("Script ended on %s.\n", date("Y-m-d h:i:s a"));

//====================================================================================================================//

/**
 * Create a session for the anonymized scan if it does not exist.
 *
 * @param $niiScan        array  Properties of the non-anonymized scan the anonymized scan
 *                               is associated with.
 * @param $anonVisitLabel string Visit label for the anonymized session.
 * @param $sessions       array  All CAPT sessions in the database.
 * @param $visitLabels    array  All visit labels in table visit.
 *
 * @return array anonymized session vlabel and anonymized session ID.
 */
function createSessionIfNeeded(array $niiScan, string $anonVisitLabel, array &$sessions, array &$visitLabels) : int
{
    global $DB;
    global $dryRun;

    //-------------------------------------------------------//
    // Ensure non-anonymized scan session exists in the DB.  //
    //-------------------------------------------------------//
    $scanSessionID = (int) $niiScan['SessionID'];
    if (!isset($sessions[$scanSessionID])) {
        die("Session $scanSessionID for {$niiScan['File']} does not exist. Skipping.\n");
    }

    //-----------------------------------------------------//
    // Check if the candidate that was scanned already has //
    // the anonymized session.                             //
    //-----------------------------------------------------//
    $query = "
        SELECT ID
        FROM session
        WHERE visit_label=:vlabel
        AND candid=:candid
    ";

    $anonSessionID = $DB->pselectOne(
        $query,
        [
          'vlabel' => $anonVisitLabel,
          'candid' => $niiScan['CandID']
        ]
    );

    //---------------------------------------------------//
    // If the anonymized session exists, returns its ID. //
    //---------------------------------------------------//
    if (!empty($anonSessionID)) {
        print "Found session $anonSessionID for anonymized scan of {$niiScan['File']}.\n";
        return (int) $anonSessionID;
    }

    //-------------------------------------//
    // Update the visit table if needed.   //
    //-------------------------------------//
    if (!in_array($anonVisitLabel, $visitLabels)) {
        if (!$dryRun) {
            $DB->insert(
                'visit',
                 [
                     'VisitName'  => $anonVisitLabel,
                     'VisitLabel' => $anonVisitLabel
                ]
            );
        }
        print "Inserted new visit $anonVisitLabel in visit table.\n";
        $visitLabels[] = $anonVisitLabel;
    }

    //------------------------------------------------------//
    // Insert anonymized session in the database.           //
    // The anonymized session will have the same properties //
    // as the non-anonymized session, except for the ID and //
    // visit label.                                         //
    //------------------------------------------------------//
    $anonSession = $sessions[$scanSessionID];
    unset($anonSession['ID']);
    $anonSession['Visit_label'] = $anonVisitLabel;

    if (!$dryRun) {
        $DB->insert('session', $anonSession);
        $anonSessionID = (int) $DB->getLastInsertID();
    } else {
        $anonSessionID = -$scanSessionID;
    }
    $sessions[$anonSessionID] = $anonSession;
    print "Created session $anonVisitLabel with ID $anonSessionID.\n";

    print "Created session $anonSessionID for anonymization of scan of {$niiScan['File']}.\n";
    return $anonSessionID;
}

/**
 * Insert the anonymized scan in the database: update tables files and parameter_files
 * with the anonymized scan properties.
 *
 * @param $anonSessionID    int    ID of the anonymized session.
 * @param $niiScanFileID       int    ID of the non-anonymized scan in table files.
 * @param $anonNiiFilePath  string Path of the anonymized scan in table files.
 * @param $anonJsonFilePath string Path of the anonymized scan's JSON sidecar in table parameter_files.
 *
 * @return int ID of the anonymized scan in table files.
 */
function insertAnonScanInDB(int $anonSessionID, string $niiScanFileID, string $anonNiiFilePath, string $anonJsonFilePath) : int
{
    global $DB;
    global $dryRun;

    //--------------------------------------------------------//
    // Insert record in table files for the anonymized scan.  //
    // The anonymized scan will have the same field values as //
    // the non-anonymized scan, except for a few selected     //
    // columns.                                               //
    //--------------------------------------------------------//
    $query = "SELECT * FROM files WHERE FileID=:fileid";
    $anonNiiScan = $DB->pselectRow($query, ['fileid' => $niiScanFileID]);

    $anonNiiScan['OutputType']   = 'anonymized';
    $anonNiiScan['SessionID']    = $anonSessionID;
    $anonNiiScan['File']         = $anonNiiFilePath;
    $anonNiiScan['SourceFileID'] = $niiScanFileID;
    $anonNiiScan['SeriesUID']    = SCRUBBED_PARAMETER_VALUE;
    unset($anonNiiScan['FileID']);

    if (!$dryRun) {
        $DB->insert('files', $anonNiiScan);
        $anonScanFileID = $DB->getLastInsertID();
    } else {
        $anonScanFileID = -$niiScanFileID;
    }
    print "Inserted anonymized scan $anonNiiFilePath in files (ID = $anonScanFileID).\n";

    //---------------------------------------------//
    // Get records from table parameter_file       //
    // associated to the non-anonymized scan.      //
    //---------------------------------------------//
    $query = "
        SELECT pt.Name, pf.Value, pf.ParameterTypeID
        FROM parameter_file pf
        JOIN parameter_type pt ON (pt.parametertypeid=pf.parametertypeid)
        WHERE FileID=:fileid
    ";
    $niiScanParameters = $DB->pselect($query, ['fileid' => $niiScanFileID]);

    //---------------------------------------------------//
    // The anonymized scan will have the same parameters //
    // as the non-anonymized scan, except a few specific //
    // ones (see below).                                 //
    //---------------------------------------------------//
    $nowTimestamp = time();
    foreach ($niiScanParameters as $niiScanParameter) {
        // anon FileID is the ID computed above
        $anonParameters['FileID']          = $anonScanFileID;
        // ParameterTypeID is the same as the one for the non-anonymized one
        $anonParameters['ParameterTypeID'] = $niiScanParameter['ParameterTypeID'];
        // InsertTime is now
        $anonParameters['InsertTime']      = $nowTimestamp;

        // The value of the parameter is the same as the non-anonymized value, except
        // if it contains PII, in which case it is scrubbed.
        if (in_array($niiScanParameter['Name'], SCAN_PARAMETERS_TO_SCRUB)) {
            $anonParameters['Value'] = SCRUBBED_PARAMETER_VALUE;
        } elseif ($niiScanParameter['Name'] == 'bids_json_file') {
            print "JSON sidecar for anonymized scan $anonNiiFilePath is $anonJsonFilePath.\n";
            $anonParameters['Value'] = $anonJsonFilePath;
        // Delete the imaging browser's thumbnail image: it does not have the proper
        // name and will be regenrated by mass_nifti_pic.py anyway
        } elseif ($niiScanParameter['Name'] == 'check_pic_filename') {
            print "Deleting parameter check_pic for anonymized scan $anonNiiFilePath.\n";
            unset($anonParameters['Value']);
        } else {
            $anonParameters['Value'] = $niiScanParameter['Value'];
        }

        if (!$dryRun) {
            $DB->insert('parameter_file', $anonParameters);
        }
    }
    print "Updated table parameter_file for anonymized scan with ID $anonScanFileID.\n";


    return $anonScanFileID;
}

/**
 * Remove all PII from a JSON sidecar.
 *
 * @param $jsonFilePathInDefacedDir Full path of the JSON sidecar in dir DEFACED_SCANS_ROOT_DIR.
 *
 * @return array the JSON scrubbed content.
 */
function getScrubbedJsonData(string $jsonFilePathInDefacedDir) : array
{
    global $config;

    //-----------------------------//
    // Read the JSON file content. //
    //-----------------------------//
    $jsonString = file_get_contents($jsonFilePathInDefacedDir);
    if ($jsonString === FALSE) {
        die("Cannot read file $jsonFilePathInDefacedDir. Aborting.\n");
    }


    //-------------------------------//
    // Decode the JSON file content. //
    //-------------------------------//
    $jsonDataArray = json_decode($jsonString, true);
    if (is_null($jsonDataArray)) {
        die("Contents of $jsonFileFullPath could not be decoded properly. Aborting.\n");
    }

    //---------------------------------------------//
    // Scrub the headers that need to be scrubbed. //
    //---------------------------------------------//
    foreach ($jsonDataArray as $jsonKey => $jsonValue) {
        if (in_array($jsonKey, (JSON_HEADERS_TO_SCRUB))) {
            $jsonDataArray[$jsonKey] = SCRUBBED_PARAMETER_VALUE;
        }
    }

    return $jsonDataArray;
}

/**
 * Create the anonymized scan file and JSON sidecar file under directory assembly_bids
 *
 * @param $nonAnonNiiFilePath string path of the non-anonymized scan relative to the MRI data dir base path.
 * @param $anonNiiFilePath    string path of the anonymized scan relative to directory assembly_bids.
 * @param $anonJsonFilePath   string path of the anonymized JSON sidecar file relative to directory assembly_bids.
 * @param $scrubbedJsonData   array  data to write in the anonymized JSON sidecar file.
 */
function createAnonJsonAndNii(
    string $nonAnonNiiFilePath,
    string $nonAnonNiiPathInDefacedDir,
    string $anonNiiFilePath,
    string $anonJsonFilePath,
    array  $scrubbedJsonData
) : void
{
    global $config;
    global $dryRun;

    $dataDirBasePath = $config->getSetting('dataDirBasepath');

    //----------------------------------------------------------------------//
    // The anonymized scan will be a copy of the non-anonymized scan, only  //
    // it's stored in a different location (anonymized visit)               //
    //----------------------------------------------------------------------//
    $anonScanDir = dirname("$dataDirBasePath$anonNiiFilePath");
    if (!file_exists($anonScanDir)) {
        if (!$dryRun) {
            if (!mkdir($anonScanDir, 0777, true)) {
                die("Failed to create directory $anonScanDir. Aborting.\n");
            }
        }
        print "Created directory $anonScanDir.\n";
    }

    if (!$dryRun) {
        if (!copy($nonAnonNiiPathInDefacedDir, "$dataDirBasePath$anonNiiFilePath")) {
            die("Copy of $nonAnonNiiPathInDefacedDir into $dataDirBasePath$anonNiiFilePath failed. Aborting.\n");
        }
    }
    print "Copied $nonAnonNiiPathInDefacedDir into $dataDirBasePath$anonNiiFilePath.\n";

    //-----------------------------------------------------//
    // Write the anonymized JSON data in the JSON sidecar  //
    //-----------------------------------------------------//
    if (!$dryRun) {
        $jsonString = json_encode($scrubbedJsonData, JSON_PRETTY_PRINT);
        if (file_put_contents("$dataDirBasePath$anonJsonFilePath", $jsonString) == false) {
            die("Failed to write file $dataDirBasePath$anonJsonFilePath. Aborting.\n");
        }
    }
    print "Wrote $dataDirBasePath$anonJsonFilePath.\n";
}

?>
