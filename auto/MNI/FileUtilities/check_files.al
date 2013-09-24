# NOTE: Derived from blib/lib/MNI/FileUtilities.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package MNI::FileUtilities;

#line 569 "blib/lib/MNI/FileUtilities.pm (autosplit into blib/lib/auto/MNI/FileUtilities/check_files.al)"
# ------------------------------ MNI Header ----------------------------------
#@NAME       : check_files
#@INPUT      : @files - a list of filenames to check for readability
#@OUTPUT     : 
#@RETURNS    : 1 if all files exist and are readable
#              0 otherwise (and prints a warning for every bad file)
#@DESCRIPTION: Makes sure that each of a list of files exists and is readable.
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : Aug 1994, Greg Ward
#@MODIFIED   : 1995/04/25, GW: gave it two possible error messages
#              1995/10/30, GW: changed so it warns and returns 0 instead 
#                              of dying
#              1997/05/02, GW: added $variants argument and trickery
#                              with files as array or array ref for
#                              backwards compatiblity
#-----------------------------------------------------------------------------
sub check_files
{
   my ($files, $variants) = @_;
   my @files;
   if (ref $files)
   {
      @files = @$files;
   }
   else
   {
      @files = @_;
      undef $variants;
   }
   my ($num_err, $new, @ok_files);

   # what $variants can be:
   #   1) array ref -- passed to test_file as is
   #   2) any other true value -- converted to undef so test_file
   #      will use default list of variant extensions
   #   3) any false value (including undefined) -- don't test variants 
   #      at all ie. pass a defined false value to test_file)

   $variants = 0 if ! $variants;
   undef $variants if $variants && ! (ref $variants eq 'ARRAY');
   croak "check_files: \$variants must be an array ref or a simple scalar"
      if (ref $variants && ref $variants ne 'ARRAY');

   $num_err = 0;
   local $_;
   foreach (@files)
   {
      next unless $_;
      $new = test_file ('-e', $_, $variants);

      if ($new)                         # the file at least exists
      {
         if (! -f $new)                 # ... but it isn't a regular file
         {
            warn "$new not a regular file\n";
            $num_err++;
            undef $new;
         }
         elsif (! -r $new)              # exists, is regular file, but is
         {                              # unreadable
            warn "$new not readable\n";
            $num_err++;
            undef $new;
         }

         push (@ok_files, $new);
      }
      else                              # file doesn't exist at all
      {	
         my $is_link = ($variants ? test_file ('-l', $_, $variants) : -l);
         if ($is_link)
         {
            warn "$_ is a dangling link (file does not exist)\n";
         }
         else
         {
            warn "$_ does not exist\n";
         }

	 $num_err++;
         push (@ok_files, undef);
      }
   }

   wantarray 
      ? return @ok_files
      : return ($num_err == 0);
}

# end of MNI::FileUtilities::check_files
1;
