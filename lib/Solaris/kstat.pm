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

