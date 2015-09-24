use Test::Most;

use Solaris::kstat;

my $k = Solaris::kstat->new;

isa_ok($k, 'Solaris::kstat',
       'Object is of right class');

# is( exists($k->{cpu}->{0}->{sys}->{cpu_ticks_kernel}), undef,
#   'CPU 0 stats should not yet exist' );


# () = keys %{$k->{cpu}->{0}->{sys}};

my $c = $k->copy();

my @k_module_keys = keys %{$k};
my @c_module_keys = keys %{$c};

cmp_bag( \@c_module_keys, \@k_module_keys,
         'Copy module keys should be complete' );

done_testing();
