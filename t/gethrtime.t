use strict;
use warnings;

use Test::Most;
use Data::Dumper;

use_ok( 'Solaris::kstat', ':all' );

my $k = Solaris::kstat->new();

my $t0 = $k->gethrtime();

sleep(1);

my $t1 = $k->gethrtime();

my $elapsed = $t1 - $t0;

diag "T0:      $t0";
diag "T1:      $t1";
diag "ELAPSED: $elapsed";

cmp_ok( $elapsed, '>', 0, "Elapsed time is > 0");
cmp_ok( $elapsed, '>=', 1_000_000_000, "Elapsed time is > 1 second in nsecs");

done_testing();
