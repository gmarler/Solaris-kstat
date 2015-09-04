use strict;
use warnings;

use Test::Most;
use Data::Dumper;

use Clone  qw( clone );

use_ok( 'Solaris::kstat', ':all' );

my $k = Solaris::kstat->new();

isa_ok($k, 'Solaris::kstat', 'hashref type is correct');

ok( exists $k->{cpu}, 'UNIX kstats exist' );

my $gen = 0;
my ($i) = 0;
my (@data);

my @cpu_instances = sort { $a <=> $b } keys %{$k->{cpu}};

diag join(", ", @cpu_instances) . "\n";

my @zero_keys = keys %{$k->{cpu}->{0}->{sys}};

diag join(", ", @zero_keys) . "\n";

while ($i < 5) {
  my ($now);

  $gen = ($gen ^ 1);
  $data[$gen] = undef;

  #$now = clone( $k->{cpu}->{0}->{sys} );
  #$now = $k->{cpu}->{0}->{sys};
  $now = $k->{cpu};

  $data[$gen] = $now->{0}->{sys};

  if ($data[$gen ^ 1]) {
    diag $data[$gen ^ 1]->{cpu_nsec_idle};
    diag $data[$gen]->{cpu_nsec_idle};
    my $value = $data[$gen]->{cpu_nsec_idle} - $data[$gen ^ 1]->{cpu_nsec_idle};
    diag "VALUE: $value";
    my $divisor = ($data[$gen]->{snaptime} - $data[$gen ^ 1]->{snaptime}) * 100.0;
    diag "DIVISOR: $divisor";
    #my $pct_idle = int($value / $divisor);
    #diag "Percent IDLE: $pct_idle";
  }

  $i++;
}

done_testing();
