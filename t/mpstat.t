use strict;
use warnings;

use Test::Most;
use Data::Dumper;

use Clone  qw( clone );
use POSIX  qw();

use_ok( 'Solaris::kstat', ':all' );

my $k = Solaris::kstat->new();

isa_ok($k, 'Solaris::kstat', 'hashref type is correct');

ok( exists $k->{cpu}, 'UNIX kstats exist' );

my $gen = 0;
my ($i) = 0;
my (@data);

#my $hz = POSIX::sysconf( &POSIX::_SC_CLK_TCK );
#diag "System Clock at $hz Hz";

my @cpu_instances = sort { $a <=> $b } keys %{$k->{cpu}};

diag join(", ", @cpu_instances) . "\n";

my @zero_keys = keys %{$k->{cpu}->{0}->{sys}};

diag join(", ", @zero_keys) . "\n";

while ($i < 5) {
  my ($now);

  $gen = ($gen ^ 1);
  $data[$gen] = undef;

  $k->update();

  $now = clone( $k->{cpu} );
  #$now = $k->{cpu}->{0}->{sys};
  #$now = $k->{cpu};

  $data[$gen] = $now->{0}->{sys};

  if ($data[$gen ^ 1]) {
    #diag $data[$gen ^ 1]->{cpu_nsec_idle};
    #diag $data[$gen]->{cpu_nsec_idle};
    my @values = ( $data[$gen]->{cpu_nsec_idle}   - $data[$gen ^ 1]->{cpu_nsec_idle},
                   $data[$gen]->{cpu_nsec_kernel} - $data[$gen ^ 1]->{cpu_nsec_kernel},
                   $data[$gen]->{cpu_nsec_user}   - $data[$gen ^ 1]->{cpu_nsec_user},
                 );

    my $divisor = ($data[$gen]->{snaptime} - $data[$gen ^ 1]->{snaptime}); # * 1000000000;
    #diag "DIVISOR: $divisor";
    my @pcts = map { my $x = $_ / $divisor;
                     my $orig = $x * 100;
                     { orig    => $orig,
                       int     => int($orig),
                       frac    => sprintf("%.9f",$orig - int($orig)),
                       pct     => int($orig + .5), 
                     };
                   } @values;

    # Use a form of Largest Remainder Method
    my $pct_total = 0;
    foreach my $component (map { $_->{pct} } @pcts) {
      $pct_total += $component;
    }
    if ( $pct_total == 100 ) { diag "No % work to do" }
    else {
      # We tried to just round things off, but it didn't work out - we're either
      # over or under 100%, so we need to go back to the originally calculated
      # data and try Largest Remainder Method
      my ($achieved_total, $leftover) = (0, 0);
      foreach my $int (map { $_->{int} } @pcts) {
        $achieved_total += $int;
      }
      $leftover = 100 - $achieved_total;
      diag "Must apportion remaining $leftover %";

      # Reset the percents back to their integer values
      foreach my $element (@pcts) {
        $element->{pct} = $element->{int};
      }

      # Get list of indices into @pct, sorted in descending order by their
      # fractional parts
      my ($index) = 0;
      my @pct_indices = 
        map  { $_->[0] }
        sort { $b->[1] <=> $a->[1] }
        map  { [ $index++, $_->{frac} ] } @pcts;

      diag "percent indices: " . Dumper( \@pct_indices );

      #if (scalar(@pct_indices) < ) {
      #
      #}
      while ($leftover-- > 0) {
        #diag Dumper( $pcts[shift(@pct_indices)] );
        $pcts[shift(@pct_indices)]->{pct}++;
      }
    }

    diag Dumper( \@pcts );

    diag "IDLE, SYS, USER: " . sprintf("%3.0f, %3.0f, %3.0f", map { $_->{pct}; } @pcts) . "\n";
    
    sleep(1);
  } else {
    sleep(1);
  }

  $i++;
}

done_testing();
