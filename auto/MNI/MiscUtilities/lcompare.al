# NOTE: Derived from blib/lib/MNI/MiscUtilities.pm.
# Changes made here will be lost when autosplit is run again.
# See AutoSplit.pm.
package MNI::MiscUtilities;

#line 207 "blib/lib/MNI/MiscUtilities.pm (autosplit into blib/lib/auto/MNI/MiscUtilities/lcompare.al)"
# Had an interesting time trying to make my `lcompare' act like
# builtin `sort', eg. so you could do any of these:
#
#    lcompare { $_[0] <=> $_[1] } @a, @b
#    $ncomp = sub { $_[0] <=> $_[1] }
#    lcompare (sub { $_[0] <=> $_[1] }, @a, @b)
#    lcompare ($ncomp, @a, @b)
#
# but it turns out that prototypes just plain aren't that flexible
# -- at least, I couldn't figure out.  Perhaps there's a reason
# that table of prototypes you could use to replace builtins doesn't
# include mysort!
#
# So I'm doing it the obvious, non-prototyped way -- caller must
# pass in explicit references (one code ref, to array refs).


# Here's some things I found out while playing around with the
# prototype version of lcompare:
#
# CODE                                     compiles ok?  result ok?
# compare (sub { $_[0] == $_[1] }, @a, @b)      yes         yes
# compare { $_[0] == $_[1] }, @a, @b            yes          no
# compare { $_[0] == $_[1] } @a, @b             yes         yes
# compare ({ $_[0] == $_[1] } @a, @b)            no
# compare ({ $_[0] == $_[1] }, @a, @b)           no

# ------------------------------ MNI Header ----------------------------------
#@NAME       : lcompare
#@INPUT      : $cmp   - [code ref] comparison function, takes 2 args
#                       and returns -1, 0, or 1, depending on whether first
#                       is less than, equal to, or greater than second
#              $alist - [array ref] first array
#              $blist - [array ref] second array
#@OUTPUT     : 
#@RETURNS    : 0 if the two arrays are equal
#              -1 if @$alist is smaller than @$blist
#              1 if @$alist is greater than @$blist
#@DESCRIPTION: Compares two arrays, element by element, and returns
#              an integer telling which is `larger'.
#@CREATED    : 1997/04/24, Greg Ward
#-----------------------------------------------------------------------------
sub lcompare # (&\@\@)
{
   my ($cmp, $alist, $blist) = @_;
   my ($i, $result);

   # goal: lcompare { $a cmp $b } [split ("", $s1)], [split ("", $s2)]
   # should be same as $s1 cmp $s2

   $result = 0;
   for $i (0 .. $#$alist)
   {
      my ($a, $b) = ($alist->[$i], $blist->[$i]);
      return 1 if !defined $b;          # list a is longer
      $result = &$cmp ($a, $b);
      return $result if $result != 0;
   }

   return -1 if $#$blist > $#$alist;	# equal up to end of a, but b longer
   return 0;                            # they're equal
}

# end of MNI::MiscUtilities::lcompare
1;
