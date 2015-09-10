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
