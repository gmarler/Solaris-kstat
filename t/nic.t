use strict;
use warnings;

use Test::Most;
use Data::Dumper;

use_ok( 'Solaris::kstat', ':all' );

my $k = Solaris::kstat->new();

isa_ok($k, 'Solaris::kstat', 'hashref type is correct');

ok( exists $k->{lo}, 'Loopback module kstat exists' );
ok( exists $k->{lo}{0}, 'Loopback module instance 0 kstat exists' );

# diag Dumper($k->{e1000g}{1}{statistics});
#foreach my $k (sort keys %{$k->{e1000g}{1}{statistics}}) {
#  diag $k;
#}

done_testing();
