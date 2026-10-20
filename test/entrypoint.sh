#!/bin/bash

# The generated environment is also sourced by production shells. Seed the container-specific Perl
# artifact first, then let that shared file configure Python, optional MINC, and LORIS-MRI paths.
export PERL5LIB="/opt/loris-perl/lib/perl5${PERL5LIB:+:$PERL5LIB}"
source /opt/loris/bin/mri/environment

# Create a writable directory with links to the imaging dataset files
replicate_raisinbread_for_mcin_dev_vm.pl /data-loris /data/loris

# Run the provided command (usually the integration test command)
exec "$@"
