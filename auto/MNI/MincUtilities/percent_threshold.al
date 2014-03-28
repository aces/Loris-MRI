# NOTE: Derived from blib/lib/MNI/MincUtilities.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package MNI::MincUtilities;

#line 329 "blib/lib/MNI/MincUtilities.pm (autosplit into blib/lib/auto/MNI/MincUtilities/percent_threshold.al)"
sub percent_threshold
{
   my ($volmin, $volmax, $percent) = @_;
   ($volmax - $volmin) * $percent + $volmin;
}

# end of MNI::MincUtilities::percent_threshold
1;
