# NOTE: Derived from blib/lib/MNI/FileUtilities.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package MNI::FileUtilities;

#line 914 "blib/lib/MNI/FileUtilities.pm (autosplit into blib/lib/auto/MNI/FileUtilities/find_program.al)"
# ------------------------------ MNI Header ----------------------------------
#@NAME       : &find_program
#@INPUT      : $program - name of program to search for
#              $path    - colon-delimited list of directories to look in
#                         (if not supplied, $ENV{"PATH"} will be used);
#                         OR a reference to a list of directories
#@OUTPUT     : 
#@RETURNS    : full path of program, or 0 if not found (also prints a 
#              warning if not found)
#@DESCRIPTION: Searches a list of directories for an executable program.
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 1995/07/20, Greg Ward
#@MODIFIED   : 1997/05/05, GW: changed into a simple front-end for 
#                          search_directories
#-----------------------------------------------------------------------------
sub find_program
{
   my ($program, $path) = @_;
   my (@path, $found, $dir, $fullpath);

   $path = $ENV{'PATH'} unless defined $path;

   if (! ref $path)              { @path = split (":", $path) }
   elsif (ref $path eq 'ARRAY')  { @path = @$path }
   else 
   {
      croak "\$path argument must be either an array ref or a scalar\n";
   }

   $dir = search_directories ($program, \@path, '-f && -x');
   return "$dir$program" if $dir;
   warn "Couldn't find program \"$program\"\n";
   return 0;
}

# end of MNI::FileUtilities::find_program
1;
