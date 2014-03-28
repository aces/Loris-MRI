# NOTE: Derived from blib/lib/MNI/MincUtilities.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package MNI::MincUtilities;

#line 301 "blib/lib/MNI/MincUtilities.pm (autosplit into blib/lib/auto/MNI/MincUtilities/volume_minmax.al)"
sub volume_minmax
{
   my ($volume) = @_;
   my ($status, $volmax, $volmin);

   (volume_min ($volume), volume_max ($volume));
}

# end of MNI::MincUtilities::volume_minmax
1;
