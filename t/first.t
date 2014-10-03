use strict;
use warnings;

use Test::Most;
use Data::Dumper;

use_ok( 'Solaris::kstat', ':all' );

my $k = Solaris::kstat->new();

isa_ok($k, 'Solaris::kstat', 'hashref type is correct');

ok( exists $k->{cpu}, 'CPU kstats exist' );
my @cpus = keys %{$k->{cpu}};
@cpus = sort { $a <=> $b } @cpus;
# Get the list of CPUs (in case there's no CPU 0), and use the first one
# There's obviously at least 1 CPU
cmp_ok( scalar(@cpus), '>=', 1, "There is at least one CPU" );

my $first_cpu = $cpus[0];

ok( exists $k->{cpu}{$first_cpu}, "CPU kstats for CPU ${first_cpu} exist" );
ok( exists $k->{cpu}{$first_cpu}{sys}, 'CPU kstats for CPU ${first_cpu} sys exist' );
ok( exists $k->{cpu}{$first_cpu}{sys}{cpu_ticks_idle},
    "There are idle CPU ticks for CPU $first_cpu" );

like( $k->{cpu}{$first_cpu}{sys}{cpu_ticks_idle}, qr/^\d+$/,
      'IDLE CPU TICKS for first CPU has a numeric value' );

done_testing();
