package Solaris::kstat;

use strict;
use warnings;
use Exporter;
use XSLoader;

use base 'Exporter';

our $VERSION        = '0.001';
our %EXPORT_TAGS    = ( 'all' => [] );
our @EXPORT_OK      = ( @{ $EXPORT_TAGS{'all'} } );

XSLoader::load('Solaris::kstat', $VERSION);

1;

=head1 NAME

Solaris::kstat - Interface to Solaris kstat

