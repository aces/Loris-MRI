# NOTE: Derived from blib/lib/MNI/MincUtilities.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package MNI::MincUtilities;

#line 747 "blib/lib/MNI/MincUtilities.pm (autosplit into blib/lib/auto/MNI/MincUtilities/get_dimension_order.al)"
# ------------------------------ MNI Header ----------------------------------
#@NAME       : &get_dimension_order
#@INPUT      : $volume - name of MINC file to get dimension names from; 
#                   OR - reference to an array containing the dim names
#@OUTPUT     : 
#@RETURNS    : $order  - ref to dimension order list
#              $perm   - ref to dimension permutation list
#@DESCRIPTION: Computes the dimension order and permutation for a MINC
#              file.
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : mincinfo
#@CREATED    : 1996/10/22, GW (from code formerly in autocrop)
#@MODIFIED   : 
#@COMMENTS   : The "order" and "permutation" jargon is entirely my
#                 own invention; I don't know if anybody else uses
#                 the same terms.  Helps me get a grip on this damn 
#                 stuff, at any rate.
#              Shouldn't actually bomb on volumes with < 3 spatial 
#                 dimensions (or with non-spatial dimensions; they will
#                 just be ignored).  However, I really don't know if
#                 it produces useful results in those cases.
#-----------------------------------------------------------------------------
sub get_dimension_order
{
   my ($volume) = @_;
   my (@dimlist, %dim_num, @order, @perm);

   %dim_num = ('xspace', 0, 'yspace', 1, 'zspace', 2);

   if ($volume && ! ref $volume)        # it's a string -- name of MINC file
   {
      my $dimlist;
      if ($Execute)
      {
         ### this fails in minc2.
         ###  $Spawner->spawn (['mincinfo', '-dimnames', $volume],
         ### this will work in minc2.
         $Spawner->spawn (['mincinfo', '-vardims', 'image', $volume],
                          stdout => \$dimlist);
         chop $dimlist;
         @dimlist = split (/\s+/, $dimlist);
      }
      else
      {
         @dimlist = qw(xspace yspace zspace);
      }
   }
   elsif (ref $volume eq 'ARRAY')
   {
      @dimlist = @$volume;
   }
   else
   {
      croak "get_dimension_order: \$volume must be either a string or " .
            "an array ref";
   }

   @dimlist = grep (/^[xyz]space$/, @dimlist);

   my ($i, $dim_num);
   for $i (0 .. $#dimlist)
   {
      $dim_num = $dim_num{$dimlist[$i]};
      $order[$i] = $dim_num;
      $perm[$dim_num] = $i;
   }

   (\@order, \@perm);
}

# end of MNI::MincUtilities::get_dimension_order
1;
