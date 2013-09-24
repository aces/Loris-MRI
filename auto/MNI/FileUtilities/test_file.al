# NOTE: Derived from blib/lib/MNI/FileUtilities.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package MNI::FileUtilities;

#line 703 "blib/lib/MNI/FileUtilities.pm (autosplit into blib/lib/auto/MNI/FileUtilities/test_file.al)"
# ------------------------------ MNI Header ----------------------------------
#@NAME       : &test_file
#@INPUT      : 
#@OUTPUT     : 
#@RETURNS    : name of the file that ultimately passes the test
#@DESCRIPTION: Perform file test(s) on a filename and, if needed, 
#              variations on that filename implied by a list of extensions.
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : Greg Ward, March 1996
#@MODIFIED   : 1997/03/06, added "pgp" extension
#              1997/05/01, changed so we always test $_ implicitly -- that
#                          way caller can supply a fancier test expression
#              1997/05/02, changed to use $_ for filename so caller can
#                          supplier fancier set of file test(s)
#-----------------------------------------------------------------------------
sub test_file
{
   my ($test, $file, $variants) = @_;
   my ($variant_re);
   local $_;

   # default list of variant extensions

   if (defined $variants)
   {
      if ($variants && ref $variants ne 'ARRAY')
      {
         croak "test_file: \$variants must be an array ref, a false " .
               "scalar value, or not supplied";
      }
   }
   else                                 # not supplied -- use default list
   {
      $variants = [qw (gz z Z)];
   }

   # At this point, if $variants is true it must be an array ref.

   $variant_re = join ("|", @$variants) if $variants;


   # If $file as supplied passes the test, immediately return success
   
   $_ = $file;
   return $_ if (eval $test);
   croak "test_file: error in \$test argument: $@" if $@;


   # OK, that didn't work -- get clever by trying out variant filenames,
   # but only if the user-supplied list of variants is not empty (see
   # check_files for an example of an empty list of variants -- it is
   # occasionally convenient!)

   if ($variants)
   {
      # First, try stripping off the variant extensions.  If that works, it
      # means the passed-in filename already had an extension (eg. it's
      # already compressed), so let's try testing the base filename.

      if (s/\.($variant_re)$//)
      {
         return $_ if (eval $test);
      }

      # Now, at this point we could be in one of two situations: either the
      # original filename is intact (the s/// didn't remove any
      # extensions), or we have stripped off an extension and the test
      # failed on the base filename.

      # In the former case ('.mnc.gz' didn't work, tried '.mnc' and it 
      # also didn't work), we'll give up now.  We could conceivably
      # try the other variant extensions on the base filename, but
      # that's just getting a little overenthusiastic.  However, if we 
      # didn't manage to strip off any existing variant extensions, we
      # should definitely test the file with all the different extensions.

      else
      {
         my $ending;
         for $ending (@$variants)
         {
            $_ = "$file.$ending";
            return $_ if (eval $test);
         }
      }
   }
   
   # If we make it to here, then all tests failed -- hey, we did our best!

   return '';
}

# end of MNI::FileUtilities::test_file
1;
