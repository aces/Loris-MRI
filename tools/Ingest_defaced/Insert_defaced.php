<?php

declare(strict_types=1);

/**
 * Register final defaced NIfTIs alongside their native originals, in the same session.
 *
 * Usage: php Insert_defaced.php [--dry-run | --commit]
 * No argument means dry run: discover, SELECT, hash, and report only.
 * --commit additionally copies images and inserts files, parameter_file, and
 * files_intermediary records. Originals, sessions, visits, JSON, and QC are untouched.
 * The new scan links to the original BIDS JSON sidecar and its freshly verified hash.
 * UIDs and acquisition metadata remain private until QC mapping and later scrubbing.
 * Dry run is not an OS sandbox: file access times and service logs may still change.
 * LORIS database credentials come from its PHP configuration, not a Python profile.
 */

// Verify these installation-specific settings before either mode is run.
const DEFACED_SCANS_ROOT_DIR = '/data/ccnaopen/data/bids_deface_test/';
const BIDS_ROOT_DIR = '/data/ccnaopen/data/assembly_bids/';
const PROJECT = 'COMPASS-ND';
const LORIS_ROOT_DIR = '/var/www/loris';

/** Discover final outputs exactly two directories below root, without following symlinks. */
function findDefacedInputs(string $root): array
{
    if (!is_dir($root) || !is_readable($root)) {
        throw new RuntimeException("Input directory is not readable: $root");
    }
    $paths = [];
    foreach (new DirectoryIterator($root) as $subjectDir) {
        if ($subjectDir->isDot() || !$subjectDir->isDir() || $subjectDir->isLink()) {
            continue;
        }
        foreach (new DirectoryIterator($subjectDir->getPathname()) as $scanDir) {
            if ($scanDir->isDot() || !$scanDir->isDir() || $scanDir->isLink()
                || strcasecmp($scanDir->getFilename(), 'QC') === 0
            ) {
                continue;
            }
            foreach (new DirectoryIterator($scanDir->getPathname()) as $entry) {
                if (!$entry->isDot() && $entry->isFile() && !$entry->isLink()
                    && preg_match('/_defaced\.nii\.gz$/', $entry->getFilename())
                ) {
                    $paths[] = $entry->getPathname();
                }
            }
        }
    }
    sort($paths);
    if (!$paths) {
        throw new RuntimeException("No final *_defaced.nii.gz inputs found in $root");
    }
    return $paths;
}

/** Hash compressed file bytes using the same MD5 and BLAKE2b-512 conventions as LORIS-MRI. */
function imageHashes(string $path): array
{
    $md5 = hash_file('md5', $path);
    $output = [];
    $status = 0;
    exec('b2sum -- ' . escapeshellarg($path), $output, $status);
    if ($md5 === false || $status !== 0
        || !preg_match('/^([a-f0-9]{128})\s/', implode("\n", $output), $matches)
    ) {
        throw new RuntimeException("Cannot hash file: $path (b2sum is required)");
    }
    return ['md5hash' => $md5, 'file_blake2b_hash' => $matches[1]];
}

/** Validate and prepare a link to the original scan's existing BIDS JSON sidecar. */
function linkedJsonParameters(array $parameters, string $base, string $bidsRoot, int $jsonHashType): array
{
    $jsonParameter = null;
    foreach ($parameters as $parameter) {
        if ($parameter['Name'] === 'bids_json_file') {
            if ($jsonParameter !== null) {
                throw new RuntimeException('Original has multiple bids_json_file parameters');
            }
            $jsonParameter = $parameter;
        }
    }
    if ($jsonParameter === null || !is_string($jsonParameter['Value'])
        || $jsonParameter['Value'] === '' || $jsonParameter['Value'][0] === '/'
    ) {
        throw new RuntimeException('Original has no relative bids_json_file reference');
    }
    $jsonPath = realpath($base . '/' . $jsonParameter['Value']);
    if ($jsonPath === false || !is_file($jsonPath) || is_link($base . '/' . $jsonParameter['Value'])
        || strpos($jsonPath, $bidsRoot . '/') !== 0
    ) {
        throw new RuntimeException('Original BIDS JSON sidecar is missing or outside assembly_bids');
    }
    $hashes = imageHashes($jsonPath);
    return [
        (int) $jsonParameter['ParameterTypeID'] => $jsonParameter['Value'],
        $jsonHashType => $hashes['file_blake2b_hash'],
    ];
}

/** Preserve acquisition parameters and UIDs; link the shared JSON sidecar and replace image hashes. */
function copiedParameters(
    array $parameters,
    array $hashes,
    array $hashTypes,
    array $jsonParameters
): array
{
    $result = [];
    foreach ($parameters as $parameter) {
        $name = $parameter['Name'];
        if ($name === 'check_pic_filename'
            || preg_match('/^bids_.*file/', $name)
            || strpos($name, 'scans_tsv_file') === 0
            || array_key_exists($name, $hashes)
        ) {
            continue;
        }
        $result[(int) $parameter['ParameterTypeID']] = $parameter['Value'];
    }
    foreach ($hashes as $name => $value) {
        $result[$hashTypes[$name]] = $value;
    }
    foreach ($jsonParameters as $type => $value) {
        $result[$type] = $value;
    }
    return $result;
}

/** Return a verified existing FileID; reject incomplete imports, conflicting records, or orphan files. */
function existingDefaced(
    $db,
    array $original,
    string $relative,
    string $destination,
    array $hashes,
    array $jsonParameters
): ?int
{
    // Both destination and source relationship must identify the same single import.
    $rows = iterator_to_array($db->pselect(
        "SELECT * FROM files WHERE File = :path
         OR (SourceFileID = :source AND OutputType = 'defaced')",
        ['path' => $relative, 'source' => $original['FileID']]
    ));
    if (!$rows) {
        if (file_exists($destination) || is_link($destination)) {
            throw new RuntimeException("Destination exists without a matching record: $destination");
        }
        return null;
    }
    if (count($rows) !== 1) {
        throw new RuntimeException("Multiple destination records for $relative");
    }
    $row = reset($rows);
    if ($row['File'] !== $relative || $row['OutputType'] !== 'defaced'
        || (int) $row['SourceFileID'] !== (int) $original['FileID']
        || (int) $row['SessionID'] !== (int) $original['SessionID']
        || !is_file($destination) || is_link($destination)
        || imageHashes($destination) !== $hashes
    ) {
        throw new RuntimeException("Existing defaced import is inconsistent: $relative");
    }
    // A filename match alone is insufficient to accept a previous run as complete.
    $links = $db->pselectOne(
        "SELECT COUNT(*) FROM files_intermediary
         WHERE Output_FileID = :output AND Input_FileID = :input AND Tool = 'defacing'",
        ['output' => $row['FileID'], 'input' => $original['FileID']]
    );
    if ((int) $links !== 1) {
        throw new RuntimeException("Missing or duplicate defacing link for $relative");
    }
    foreach ($hashes as $name => $value) {
        $stored = $db->pselectOne(
            'SELECT pf.Value FROM parameter_file pf
             JOIN parameter_type pt USING (ParameterTypeID)
             WHERE pf.FileID = :file AND pt.Name = :name',
            ['file' => $row['FileID'], 'name' => $name]
        );
        if ($stored !== $value) {
            throw new RuntimeException("Stored $name does not match $relative");
        }
    }
    foreach ($jsonParameters as $type => $value) {
        $stored = $db->pselectOne(
            'SELECT Value FROM parameter_file WHERE FileID = :file AND ParameterTypeID = :type',
            ['file' => $row['FileID'], 'type' => $type]
        );
        if ($stored !== $value) {
            throw new RuntimeException("Stored BIDS JSON link does not match for $relative");
        }
    }
    return (int) $row['FileID'];
}

/**
 * Commit one scan and its provenance link, cleaning up the new file on handled failure.
 * Earlier scans remain committed if a later scan fails; reruns verify completed scans.
 * Filesystem writes are not transactional: a crash can leave an orphan requiring review.
 */
function ingestScan($db, array $plan, array $hashTypes): int
{
    $sourceHandle = null;
    $destinationHandle = null;
    $created = false;
    if (!$db->beginTransaction()) {
        throw new RuntimeException('Cannot start transaction');
    }
    try {
        // Lock and recheck the original so a concurrent import cannot bypass the duplicate check.
        $original = $db->pselectRow(
            'SELECT * FROM files WHERE FileID = :id FOR UPDATE',
            ['id' => $plan['original']['FileID']]
        );
        if ($original !== $plan['original']) {
            throw new RuntimeException('Original record changed after preflight');
        }
        $existing = existingDefaced(
            $db, $original, $plan['relative'], $plan['destination'], $plan['hashes'],
            $plan['jsonParameters']
        );
        if ($existing !== null) {
            $db->rollBack();
            return $existing;
        }
        // Exclusive creation protects existing files even if one appeared after preflight.
        $sourceHandle = fopen($plan['input'], 'rb');
        $destinationHandle = fopen($plan['destination'], 'xb');
        $created = is_resource($destinationHandle);
        if (!is_resource($sourceHandle) || !$created
            || stream_copy_to_stream($sourceHandle, $destinationHandle) === false
            || !fflush($destinationHandle)
        ) {
            throw new RuntimeException('Cannot exclusively copy input to destination');
        }
        fclose($sourceHandle);
        $sourceHandle = null;
        fclose($destinationHandle);
        $destinationHandle = null;
        // Detect truncated copies or inputs that changed since preflight.
        if (imageHashes($plan['destination']) !== $plan['hashes']) {
            throw new RuntimeException('Copied image differs from preflight input');
        }
        if (!chmod($plan['destination'], fileperms(dirname($plan['destination'])) & 0666)) {
            throw new RuntimeException('Cannot set destination permissions');
        }
        // Keep SessionID, SeriesUID, scan type, and acquisition fields from the native row.
        $record = $original;
        unset($record['FileID']);
        $record['File'] = $plan['relative'];
        $record['OutputType'] = 'defaced';
        $record['SourceFileID'] = $original['FileID'];
        $record['InsertTime'] = time();
        $user = function_exists('posix_geteuid') ? posix_getpwuid(posix_geteuid()) : false;
        if (!$user || empty($user['name'])) {
            throw new RuntimeException('Cannot determine the effective operating-system user');
        }
        $record['InsertedByUserID'] = $user['name'];
        $db->insert('files', $record);
        $fileID = (int) $db->getLastInsertID();
        // Do not claim the thumbnail belongs to this new image. but claim the sidecar does.
        $parameters = iterator_to_array($db->pselect(
            'SELECT pt.Name, pf.Value, pf.ParameterTypeID FROM parameter_file pf
             JOIN parameter_type pt USING (ParameterTypeID) WHERE pf.FileID = :file',
            ['file' => $original['FileID']]
        ));
        $jsonParameters = linkedJsonParameters(
            $parameters, $plan['base'], $plan['bidsRoot'], $plan['jsonHashType']
        );
        if ($jsonParameters !== $plan['jsonParameters']) {
            throw new RuntimeException('Original BIDS JSON link changed after preflight');
        }
        foreach (copiedParameters(
            $parameters, $plan['hashes'], $hashTypes, $jsonParameters
        ) as $type => $value) {
            $db->insert('parameter_file', [
                'FileID' => $fileID, 'ParameterTypeID' => $type,
                'Value' => $value, 'InsertTime' => time(),
            ]);
        }
        // Record processing provenance in addition to files.SourceFileID.
        $db->insert('files_intermediary', [
            'Output_FileID' => $fileID, 'Input_FileID' => $original['FileID'],
            'Tool' => 'defacing',
        ]);
        if (!$db->commit()) {
            throw new RuntimeException('Database commit failed');
        }
        return $fileID;
    } catch (Throwable $error) {
        if (is_resource($sourceHandle)) {
            fclose($sourceHandle);
        }
        if (is_resource($destinationHandle)) {
            fclose($destinationHandle);
        }
        if ($db->inTransaction()) {
            $db->rollBack();
        }
        // Only remove the destination created by this attempt, never a pre-existing file.
        if ($created && !unlink($plan['destination'])) {
            fwrite(STDERR, "Cleanup required: {$plan['destination']}\n");
        }
        throw $error;
    }
}

/** Preflight every input before allowing any ingestion writes; return a shell exit status. */
function main(array $arguments): int
{
    // Help and argument validation run before LORIS initialization or database access.
    if ($arguments === ['--help']) {
        echo "Usage: php Insert_defaced.php [--dry-run | --commit]\n";
        echo "Default: dry run. Preserves UIDs; does not write JSON, sessions, visits, or QC.\n";
        echo 'Input: ' . DEFACED_SCANS_ROOT_DIR . "\nProject: " . PROJECT . "\n";
        return 0;
    }
    if ($arguments !== [] && $arguments !== ['--dry-run'] && $arguments !== ['--commit']) {
        throw new InvalidArgumentException('Use --help, --dry-run, or --commit');
    }
    $commit = $arguments === ['--commit'];
    $inputs = findDefacedInputs(DEFACED_SCANS_ROOT_DIR);
    // CLI bootstrap supplies $config and $DB; it does not use the MRI Python profile.
    require LORIS_ROOT_DIR . '/tools/generic_includes.php';
    $base = realpath($config->getSetting('dataDirBasepath'));
    $bidsRoot = realpath(BIDS_ROOT_DIR);
    if ($base === false || $bidsRoot === false || strpos($bidsRoot . '/', $base . '/') !== 0) {
        throw new RuntimeException('BIDS root must exist within configured dataDirBasepath');
    }
    // Require existing lookup types rather than silently creating parameter types.
    $hashTypes = [];
    foreach (['md5hash', 'file_blake2b_hash'] as $name) {
        $type = $DB->pselectOne(
            'SELECT ParameterTypeID FROM parameter_type WHERE Name = :name', ['name' => $name]
        );
        if (!$type) {
            throw new RuntimeException("Required parameter type is missing: $name");
        }
        $hashTypes[$name] = (int) $type;
    }
    $jsonHashType = $DB->pselectOne(
        'SELECT ParameterTypeID FROM parameter_type WHERE Name = :name',
        ['name' => 'bids_json_file_blake2b_hash']
    );
    if (!$jsonHashType) {
        throw new RuntimeException('Required parameter type is missing: bids_json_file_blake2b_hash');
    }
    $jsonHashType = (int) $jsonHashType;
    // Restrict matching to native, source-less records in the configured project.
    $originals = [];
    foreach ($DB->pselect(
        "SELECT f.* FROM files f JOIN session s ON s.ID = f.SessionID
         JOIN Project p ON p.ProjectID = s.ProjectID
         WHERE p.Name = :project AND f.OutputType = 'native' AND f.SourceFileID IS NULL",
        ['project' => PROJECT]
    ) as $row) {
        $originals[basename($row['File'])][] = $row;
    }
    echo $commit ? "COMMIT requested; preflighting all inputs first.\n" : "DRY RUN; no ingestion writes.\n";
    echo "status\toriginal_file_id\tdefaced_file_id\tinput\tdestination\n";
    $plans = [];
    $seen = [];
    $errors = 0;
    foreach ($inputs as $input) {
        try {
            // Strip only the terminal processing suffix; keep subject, session, run, and part entities.
            $name = preg_replace('/_defaced\.nii\.gz$/', '.nii.gz', basename($input));
            $matches = $originals[$name] ?? [];
            if (count($matches) !== 1) {
                throw new RuntimeException('Expected one native original; found ' . count($matches));
            }
            $original = $matches[0];
            if (isset($seen[$original['FileID']])) {
                throw new RuntimeException('Multiple inputs map to the same original');
            }
            $seen[$original['FileID']] = true;
            // Resolve the real path and reject originals outside the intended BIDS tree.
            $originalPath = realpath($base . '/' . $original['File']);
            if ($originalPath === false || !is_file($originalPath)
                || strpos($originalPath, $bidsRoot . '/') !== 0
                || !is_writable(dirname($originalPath))
            ) {
                throw new RuntimeException('Original must exist inside BIDS root with a writable directory');
            }
            // Preserve the input basename and store the destination relative to dataDirBasepath.
            $destination = dirname($originalPath) . '/' . basename($input);
            $relative = substr($destination, strlen($base) + 1);
            if (strlen($relative) > 255) {
                throw new RuntimeException('Destination exceeds files.File length');
            }
            $hashes = imageHashes($input);
            $parameters = iterator_to_array($DB->pselect(
                'SELECT pt.Name, pf.Value, pf.ParameterTypeID FROM parameter_file pf
                 JOIN parameter_type pt USING (ParameterTypeID) WHERE pf.FileID = :file',
                ['file' => $original['FileID']]
            ));
            $jsonParameters = linkedJsonParameters($parameters, $base, $bidsRoot, $jsonHashType);
            $existing = existingDefaced(
                $DB, $original, $relative, $destination, $hashes, $jsonParameters
            );
            // READY needs insertion; EXISTS passed file, hash, session, and provenance checks.
            printf("%s\t%d\t%s\t%s\t%s\n", $existing === null ? 'READY' : 'EXISTS',
                $original['FileID'], $existing ?? '', $input, $relative);
            if ($existing === null) {
                $plans[] = compact(
                    'input', 'original', 'destination', 'relative', 'hashes',
                    'jsonParameters', 'base', 'bidsRoot', 'jsonHashType'
                );
            }
        } catch (Throwable $error) {
            $errors++;
            fwrite(STDERR, "ERROR $input: {$error->getMessage()}\n");
        }
    }
    printf("Preflight: %d inputs, %d ready, %d errors.\n", count($inputs), count($plans), $errors);
    // Even --commit performs no ingestion if any input fails preflight.
    if ($errors !== 0) {
        fwrite(STDERR, "No ingestion writes performed; resolve all preflight errors first.\n");
        return 1;
    }
    // This is the only route to image copies and database inserts; dry run ends below.
    if ($commit) {
        foreach ($plans as $plan) {
            $fileID = ingestScan($DB, $plan, $hashTypes);
            printf("IMPORTED\t%d\t%d\t%s\t%s\n", $plan['original']['FileID'],
                $fileID, $plan['input'], $plan['relative']);
        }
    }
    return 0;
}

// Including this file for isolated tests defines helpers without initializing LORIS.
if (realpath($_SERVER['SCRIPT_FILENAME'] ?? '') === __FILE__) {
    try {
        exit(main(array_slice($argv, 1)));
    } catch (Throwable $error) {
        fwrite(STDERR, "ERROR: {$error->getMessage()}\n");
        exit(1);
    }
}
