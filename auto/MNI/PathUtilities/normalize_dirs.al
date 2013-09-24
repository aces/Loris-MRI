# NOTE: Derived from blib/lib/MNI/PathUtilities.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package MNI::PathUtilities;

#line 144 "blib/lib/MNI/PathUtilities.pm (autosplit into blib/lib/auto/MNI/PathUtilities/normalize_dirs.al)"
# ------------------------------ MNI Header ----------------------------------
#@NAME       : normalize_dirs
#@INPUT      : list of directories 
#@OUTPUT     : (arguments modified in place)
#@RETURNS    : 
#@DESCRIPTION: Modifies a list of directory names in place so that they
#              all either end in a slash, or are empty.
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 1997/05/26, GPW
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub normalize_dirs
{
   # add trailing slash, etc.  -- should replace ensure_trailing_slash
   # (better name, more general)

   foreach (@_)
   {
      $_ .= '/' unless ! defined $_ || $_ eq '' || substr ($_, -1, 1) eq '/';
   }
}

# end of MNI::PathUtilities::normalize_dirs
1;
