# NOTE: Derived from blib/lib/MNI/FileUtilities.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package MNI::FileUtilities;

#line 826 "blib/lib/MNI/FileUtilities.pm (autosplit into blib/lib/auto/MNI/FileUtilities/search_directories.al)"
# ------------------------------ MNI Header ----------------------------------
#@NAME       : search_directories
#@INPUT      : $file - name of file to search for
#              @dirs - list of directories to search in.  Note that
#                 the empty string may be used to denote the current 
#                 directory.
#              $test - file-test operator expression used to determine
#                 if a file "exists" in a given directory
#@OUTPUT     : 
#@RETURNS    : The directory where $file was found, or undef if it wasn't.
#              The directory is returned in a form suitable for directly
#              concatenating with the filename, i.e. either as an empty
#              string (current directory) or with a trailing slash.
#@DESCRIPTION: Searches a list of directories for a single file.
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 1994/09/16, Greg Ward
#@MODIFIED   : 1997/04/28, GW: changed to take an array ref for list of dirs,
#                          and allowed caller-supplied test code
#-----------------------------------------------------------------------------
sub search_directories
{
   my ($file, $dirs, $test) = @_;
   my ($dir, $found);

   croak ("dirs argument must be an array ref") unless ref $dirs eq 'ARRAY';
   $test = '-e' unless defined $test;

   my @dirs = @$dirs;                   # so we don't clobber caller's data
   normalize_dirs (@dirs);
   $found = 0;
   local $_;
   foreach $dir (@dirs)
   {
      $_ = $dir . $file;
      $found = eval $test;
      croak ("bad test: $test ($@)") if $@;
      return $dir if $found;
   }

   return undef;
}

# end of MNI::FileUtilities::search_directories
1;
