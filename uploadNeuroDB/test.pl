#! /usr/bin/perl

use strict;
use warnings;
use NeuroDB::DBI;
use NeuroDB::MRI;
use NeuroDB::File;



my $scan_type   = 72;
my $pname       = "MTL0572_308556_PREBL00";
my $candID      = 308556;
my $visit_label = "PREBL00";

{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/prod" }

my $dbh     = &NeuroDB::DBI::connect_to_db(@Settings::db);
my $message = "\n==> Successfully connected to database \n";

# load minc file (not part of MRI code)
my $minc = "/data/preventAD/data/assembly/308556/PREBL00/mri/native/PreventAD_308556_PREBL00_greT2star_001.mnc";
my $file = NeuroDB::File->new(\$dbh);
$file->loadFileFromDisk($minc);
NeuroDB::MRI::mapDicomParameters(\$file);
$file->setFileData('SeriesUID',      "1.3.12.2.1107.5.2.32.35442.2016072715533638881993475.0.0.0"),
$file->setFileData('TarchiveSource', "4002133"),
$file->setFileData('File',           "assembly/308556/PREBL00/mri/native/PreventAD_308556_PREBL00_greT2star_001.mnc"),

############# BEGINNING OF THE LOGIC ###########

## Step 1 - select all distinct exclude and warning headers for the scan type
my $query = "SELECT DISTINCT(Header) FROM mri_protocol_checks "
    . "WHERE Scan_type=? AND Severity=?";
my $sth   = $dbh->prepare($query);

# grep the excluded headers from mri_protocol_check for the scan type
my @exclude_headers;
$sth->execute($scan_type, 'exclude');
while (my $check = $sth->fetchrow_hashref()) {
    push(@exclude_headers, $check->{'Header'});
}

# grep the warning headers from mri_protocol_check for the scan type
my @warning_headers;
$sth->execute($scan_type, 'warning');
while (my $check = $sth->fetchrow_hashref()) {
    push(@warning_headers, $check->{'Header'});
}

## Step 2 - loop through all headers with 'exclude' severity for the scan type
# to check if the value in the file is in the valid range. If it is not in a
# valid range, then will return 'exclude'

my %validExcludeFields = loop_through_protocol_violations_checks(
    $dbh, $scan_type, 'exclude', \@exclude_headers, $file
);

## if there are any reasons to exclude the scan, log it to mri_violations
if (%validExcludeFields) {
    insert_into_mri_violations_log(
        $dbh, \%validExcludeFields, 'exclude', $pname, $candID, $visit_label, $file
    );
    return ('exclude');
}

## Step 3 - loop through all headers with 'warning' severity for the scan type
# to check if the value in the file is in the valid range. If it is not in a
# valid range, then will return 'warn'

my %validWarningFields = loop_through_protocol_violations_checks(
    $dbh, $scan_type, 'warning', \@warning_headers, $file
);

if (%validWarningFields) {
    insert_into_mri_violations_log(
        $dbh, \%validWarningFields, 'warning', $pname, $candID, $visit_label, $file
    );
    return ('warn');
}

## Step 4 - if we end up here, then the file passes the extra validation
# checks and return 'pass'

return ('pass');

exit 0;

sub loop_through_protocol_violations_checks {
    my ($dbh, $scan_type, $severity, $headers, $file) = @_;

    my %valid_fields; # will store all information about what fails

    # query to fetch list of valid protocols in mri_protocol_checks table
    my $query = "SELECT * FROM mri_protocol_checks "
        . "WHERE Scan_type=? AND Severity=? AND Header=?";
    my $sth   = $dbh->prepare($query);

    # loop through all severity headers for the scan type and check if in the
    # value of the header in the file fits one of the valid range present in
    # mri_protocol_checks
    foreach my $header (@$headers) {
        # get the value from the file
        my $value = $file->getParameter($header);

        # execute query for $scan_type, $severity, $header
        $sth->execute($scan_type, $severity, $header);

        # grep all valid ranges and regex to compare with value in the file
        my (@valid_ranges, @valid_regexs);
        while (my $check = $sth->fetchrow_hashref()) {
            push(@valid_ranges, $check->{'ValidRange'}) if $check->{'ValidRange'};
            push(@valid_regexs, $check->{'ValidRegex'}) if $check->{'ValidRegex'};
        }

        # go to the next header if did not find any checks for that scan
        # type, severity and header
        next if (!@valid_ranges && !@valid_regexs);

        # loop through all checks
        my $is_valid;
        my (@failed_valid_ranges, @failed_valid_regexs);
        foreach my $valid_range (@valid_ranges) {
            if ($valid_range && (NeuroDB::MRI::in_range($value,
                $valid_range))) {
                $is_valid = 1;
            } else {
                push(@failed_valid_ranges, $valid_range);
            }
        }
        foreach my $valid_regex (@valid_regexs) {
            if ($valid_regex && $value =~ /$valid_regex/) {
                $is_valid = 1;
            } else {
                push(@failed_valid_regexs, $valid_regex);
            }
        }

        # go to the next header if the value from the file fits the
        # value in one of the valid ranges or regex set for that scan type,
        # header and severity
        next if $is_valid;

        $valid_fields{$header}{ScanType}    = $scan_type;
        $valid_fields{$header}{HeaderValue} = $value;
        $valid_fields{$header}{ValidRanges} = \@failed_valid_ranges;
        $valid_fields{$header}{ValidRegexs} = \@failed_valid_regexs;
    }

    return %valid_fields;
}

sub insert_into_mri_violations_log {
    my ($dbh, $valid_fields, $severity, $pname, $candID, $visit_label, $file) = @_;

    my $log_query = "INSERT INTO mri_violations_log"
                    . "("
                        . "SeriesUID, TarchiveID,  MincFile,   PatientName, "
                        . " CandID,   Visit_label, Scan_type,  Severity, "
                        . " Header,   Value,       ValidRange, ValidRegex "
                    . ") VALUES ("
                        . " ?,        ?,           ?,          ?, "
                        . " ?,        ?,           ?,          ?, "
                        . " ?,        ?,           ?,          ? "
                    . ")";
#    if ($this->{debug}) {
#        print $query . "\n";
#    }
    my $log_sth = $dbh->prepare($log_query);

    # foreach header, concatenate arrays of ranges into a string
    foreach my $header (keys(%$valid_fields)) {
        my $valid_range_str  = "NULL";
        my $valid_regex_str  = "NULL";
        my @valid_range_list = @{ $valid_fields->{$header}{ValidRanges} };
        my @valid_regex_list = @{ $valid_fields->{$header}{ValidRegexs} };

        if (@valid_range_list) {
            $valid_range_str = join(',', @valid_range_list);
        }
        if (@valid_regex_list) {
            $valid_regex_str = join(',', @valid_regex_list);
        }
        $file->setFileData('Caveat', 1) if ($severity eq 'warning');

        $log_sth->execute(
            $file->getFileDatum('SeriesUID'),
            $file->getFileDatum('TarchiveSource'),
            $file->getFileDatum('File'),
            $pname,
            $candID,
            $visit_label,
            $valid_fields->{$header}{ScanType},
            $severity,
            $header,
            $valid_fields->{$header}{HeaderValue},
            $valid_range_str,
            $valid_regex_str
        );
    }
}