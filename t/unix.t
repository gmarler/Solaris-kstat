use strict;
use warnings;

use Test::Most;
use Data::Dumper;

use_ok( 'Solaris::kstat', ':all' );

my $k = Solaris::kstat->new();

isa_ok($k, 'Solaris::kstat', 'hashref type is correct');

ok( exists $k->{unix}, 'UNIX kstats exist' );

ok( exists $k->{unix}{0}, "UNIX kstat instance 0 exists" );

done_testing();
