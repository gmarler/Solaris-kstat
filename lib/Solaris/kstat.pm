package Solaris::kstat;

use strict;
use warnings;
use XSLoader;

# VERSION
# ABSTRACT: Solaris kstat consumer, implemented in Perl XS with 64-bits

XSLoader::load('Solaris::kstat', $VERSION);

1;

=head1 NAME

Solaris::kstat - Interface to Solaris kstat

=head1 SYNOPSIS

  ## Create the object
  my $k = Solaris::kstat->new;

  ## Prime the kstat to auto-collect cpu:<instances>:sys stats via the magic of
  ## XS ties:
  foreach my $instance ( keys %{$k->{cpu}} ) {
    () = each %{$k->{cpu}->{$instance}->{sys}};
  }

  ## After the above, each call to $k->update will now only update the
  ## cpu:<instances>:sys portion of the kstat chain into the hash.  You can use
  ## the $k->copy() method to get a pure hash without any kind of magic, which
  ## which to do comparisons:
  my @kstat_history;
  my $generation = 0;
  $kstat_history[$generation] = $k->copy();

  while (1) {
    $k->update();
    $generation = $generation ^ 1;
    $kstat_history[$generation] = $k->copy();

    foreach my $cpu (sort { $a <=> $b } keys %{$kstat_history[$generation]->{cpu}}) {
      my $time_pct =
        (($kstat_history[$generation]->{cpu}->{$cpu}->{sys}->{cpu_nsec_idle} -
          $kstat_history[$generation ^ 1]->{cpu}->{$cpu}->{sys}->{cpu_nsec_idle}
           )   /
         ( $kstat_history[$generation]->{cpu}->{$cpu}->{sys}->{snaptime} -
           $kstat_history[$generation ^ 1]->{cpu}->{$cpu}->{sys}->{snaptime}
         )) * 100;
      say "CPU: $cpu is $time_pct IDLE";
    }
    # Probably best to use nanosleep() to sleep for the remainder of the second
    sleep(1);
  }


=head1 NOTES ON IMPLEMENTATION

This implementation is derived from the OpenSolaris/Illumos Sun::Solaris::Kstat
implementation, which, like the one delivered with Solaris natively, had a few
shortcomings in practice:

* It's compiled 32-bit, whereas a large number of kstat values are 64-bit.  The
conversion to floating point tends to lose accuracy.

* There appears to be issues with memory leaks when trying to create more than
one object of the module at a time.

* The entire point of kstats is to have the last measurement, and the current
measurement, for comparison.  If you cannot have 2 instances of the object, this
makes such comparisons hard.

* The useful tie magic has subtle drawbacks, liking making it impossible to clone
(to get around the above issue) using Clone, Storable::dclone, or Data::Clone
to create clone copies for comparison.

Here is the internal structure of what the XS module builds when you create a
Solaris::kstat instance:

  $k = { # modules as keys
         module1 => { # instances as keys
                      instance1 => { # names as keys
                                     name1 => { # This hashref has magic
                                                stat1 => value1,hl
                                                ...
                                              },
                                     ...
                                   },
                      ...
                    },
         ...
       };

The top 3 levels of the hashref maps to the module:instance:name tuple that
kstat provides.  These top 3 levels are always created, regardless of whether
you access them, as the kstat chain is initially read.  These top 3 hashrefs are
"normal" in the sense that they're just plain Perl hashes.

The 4th level/hashref of the data structure maps to the 'statistic' portion of
the module:instance:name:statistic tuple of a kstat, and has 2 kinds of magic:

* Extended or '~' magic, which contains the Kstatinfo_t structure the XS module
defines, and which contains a pointer to the kstat_t

* Tie or 'P' magic, which provides the tie implementation for this hashref
alone.

The upshot of all this is that only the 4th level hashref is special, and it's
only populated if it's read.  Otherwise, it's just a blank placeholder.

=head1 METHODS

=head2 new()

Create a new Solaris::kstat object.  This returns a tied hashref, which can be
dereferenced by successive kstat keys.

=cut

=head2 update()

By default, once a kstat has been referenced, it will never update again of it's
own volition.  That's what the update() method is for.  It simply resnapshots the
portion of the kstat chain the tied hashref refers to.

NOTE: It's very common to want to save and compare the previous kstat snapshot;
don't make the mistake of trying to just assign the hashref to a variable; it'll
change out from under you on the next update(), and you'll just have 2 copies of
the same kstat chain.

Instead, use the deep-copy clone() function from the Clone module to make copies
of the hashref recursively.

=cut

=head2 copy()

This creates a pure perl hash (all magic is gone) of the kstat data actually
read to this point in the Solaris::kstat object.  This has the benefit of making
the copy efficient (rather than traversing the entire kstat chain every time),
as well as not having to worry about the tie or extended magic attached to
the object.

These copies can then easily be used for kstat comparisons, which is the most
common use case.

=cut

=head1 UTILITY FUNCTIONS

=head2 gethrtime()

Exposes the native gethrtime() function from Solaris, so we don't have to mess
with fractional seconds, and can use unsigned 64-bit nanosecond resolution
counters.

Returns a 64-bit integer, which is what an hrtime_t resolves to anyway.

This implies that this module can only operate with a 64-bit Perl.

=cut
