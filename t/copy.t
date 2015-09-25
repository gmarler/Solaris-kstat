use Test::Most;

use Solaris::kstat;
use Data::Dumper;

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

#foreach my $module (@k_module_keys) {
#  my @k_instance_keys = keys %{$k->{$module}};
#  my @c_instance_keys = keys %{$c->{$module}};
#  cmp_bag( \@c_instance_keys, \@k_instance_keys,
#           "Copy of instance keys for module $module is complete" );
#  foreach my $instance (@k_instance_keys) {
#    my @k_name_keys = keys %{$k->{$module}->{$instance}};
#    my @c_name_keys = keys %{$c->{$module}->{$instance}};
#    cmp_bag( \@c_name_keys, \@k_name_keys,
#             "Copy of name keys for instance $instance of module $module is complete" );
#    # foreach my $name (@k_name_keys) {
#    #   my @k_stat_keys = keys %{$k->{$module}->{$instance}->{$name}};
#    #   my @c_stat_keys = keys %{$c->{$module}->{$instance}->{$name}};
#    #   cmp_bag( \@c_stat_keys, \@k_stat_keys,
#    #            "Copy of stat keys for $module:$instance:$name is complete" );
#
#    #   #foreach my $stat (@k_stat_keys) {
#    #   #  is( $c->{$module}->{$instance}->{$name}->{$stat},
#    #   #      $k->{$module}->{$instance}->{$name}->{$stat} );
#    #   #}
#    # }
#  }
#}

my @k_cpu0_stat_keys = keys %{$k->{cpu}->{0}->{sys}};
my @c_cpu0_stat_keys = keys %{$c->{cpu}->{0}->{sys}};

cmp_bag( \@c_cpu0_stat_keys, \@k_cpu0_stat_keys,
         'Copy of CPU 0 stat keys should be complete' );

foreach my $stat (@k_cpu0_stat_keys) {
  is( $c->{cpu}->{0}->{sys}->{$stat},
      $k->{cpu}->{0}->{sys}->{$stat},
      "Value of " . '$k->{cpu}->{0}->{sys}->{' . $stat . '} should have been copied' );
}

#diag Dumper( [ keys %{$k->{cpu}->{0}->{sys}} ] );
#diag Dumper( [ keys %{$c->{cpu}->{0}->{sys}} ] );

done_testing();
