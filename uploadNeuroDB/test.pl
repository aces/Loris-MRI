#! /usr/bin/perl

use strict;
use warnings;
use NeuroDB::DBI;
use NeuroDB::MRI;

my $scan_type=72;

{ package Settings; do "$ENV{LORIS_CONFIG}/.loris_mri/prod" }

my $dbh     = &NeuroDB::DBI::connect_to_db(@Settings::db);
my $message = "\n==> Successfully connected to database \n";

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

## Step 2 - loop through all exclude headers for the scan type to check if in
#  valid range

my %validExcludeFields = loop_through_protocol_violations(
    $scan_type, 'exclude', @exclude_headers #, $file
);

## if there are any reasons to exclude the scan, log it to mri_violations
if (%validExcludeFields) {
    print "yeah";

    return ('exclude', )
}

my %validWarningFields = loop_through_protocol_violations(
    $scan_type, 'warning', @warning_headers #, $file
);

exit 0;

sub loop_through_protocol_violations {
    my ($scan_type, $severity, @headers) = @_;
    # my ($scan_type, $severity, $headers, $file) = @_;

    my %valid_fields; # will store all information about what fails

    # query to fetch list of valid protocols in mri_protocol_checks table
    my $query = "SELECT * FROM mri_protocol_checks "
        . "WHERE Scan_type=? AND Severity=? AND Header=?";
    my $sth   = $dbh->prepare($query);

    # loop through all severity headers for the scan type and check if in the
    # value of the header in the file fits one of the valid range present in
    # mri_protocol_checks
    foreach my $header (@headers) {
        # get the value from the file
        #my $value = $file->getParameter($header);
        my $value = 512;

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

        $valid_fields{$header}{ValidRanges} = \@failed_valid_ranges;
        $valid_fields{$header}{ValidRegexs} = \@failed_valid_regexs;
    }

    return %valid_fields;
}
