use strict;
use warnings;

use Test::Most;
use Data::Dumper;

use_ok( 'Solaris::kstat', ':all' );

my $k = Solaris::kstat->new();

isa_ok($k, 'Solaris::kstat', 'hashref type is correct');

ok( exists $k->{unix}->{0}->{sysinfo}, 'sysinfo kstats exist' );

# TODO: Test for the known keys in sysinfo

#diag Dumper( $k->{unix}->{0}->{sysinfo} );

done_testing();
