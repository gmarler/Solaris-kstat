use strict;
use warnings;

use Test::Most;
use Data::Dumper;

use_ok( 'Solaris::kstat', ':all' );

my $k = Solaris::kstat->new();

isa_ok($k, 'Solaris::kstat', 'hashref type is correct');

ok( exists $k->{unix}->{0}->{dnlcstats}, 'DNLC kstats exist' );
ok( exists $k->{unix}{0}{dnlcstats},     'DNLC kstats #2 exist' );

diag Dumper( $k->{unix}->{0}->{dnlcstats} );

done_testing();
