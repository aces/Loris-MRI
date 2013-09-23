# NOTE: Derived from blib/lib/MNI/FileUtilities.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package MNI::FileUtilities;

#line 980 "blib/lib/MNI/FileUtilities.pm (autosplit into blib/lib/auto/MNI/FileUtilities/find_programs.al)"
# ------------------------------ MNI Header ----------------------------------
#@NAME       : &find_programs
#@INPUT      : @$programs  - list of programs to search for
#              $path       - reference to list of directories to search
#                            (OR a colon-delimited string)
#@OUTPUT     : 
#@RETURNS    : list of found programs (as full pathnames)
#              OR empty list (if there were any missing programs)
#@DESCRIPTION: Searches for each program specified in the specified search
#              path.
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : &find_program
#@CREATED    : 1995/12/08, Greg Ward
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub find_programs
{
   my ($programs, $path) = @_;
   my ($missing, $prog, $found, @found);

   # We search for *all* requested programs, even if one isn't found --
   # that way, the user will see error messages for all missing programs,
   # not just the one that happens to turn up missing first.

   $missing = 0;
   foreach $prog (@$programs)
   {
      $found = &find_program ($prog, $path);
      $missing++ if ! $found;
      push (@found, $found);
   }
   return @found if $missing == 0;
   return ();
}

# end of MNI::FileUtilities::find_programs
1;
