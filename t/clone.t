use Test::Most;

use Solaris::kstat;

my $k = Solaris::kstat->new;

isa_ok($k, 'Solaris::kstat',
       'Object is of right class');

diag '$k->{cpu}';
$k->{cpu};
diag '$k->{cpu}->{0}';
$k->{cpu}->{0};
diag '$k->{cpu}->{0}->{sys}';
$k->{cpu}->{0}->{sys};

diag 'exists($k->{cpu}->{0}->{sys})';
exists($k->{cpu}->{0}->{sys});

() = keys %{$k->{cpu}->{0}->{sys}};
#foreach my $key (keys %{$k->{cpu}->{0}->{sys}}) {
  # exists( $k->{cpu}->{0}->{sys}->{$key} );
  # $junk = $k->{cpu}->{0}->{sys}->{$key};
  # if ($key eq "snaptime") {
  #   diag "$k->{cpu}->{0}->{sys}->{$key}"; 
  # }
#}
#  
#  sleep 1;
#  
#  foreach my $key (keys %{$k->{cpu}->{0}->{sys}}) {
#    exists( $k->{cpu}->{0}->{sys}->{$key} );
#    $junk = $k->{cpu}->{0}->{sys}->{$key};
#    if ($key eq "snaptime") {
#      diag "$k->{cpu}->{0}->{sys}->{$key}"; 
#    }
#  }


done_testing();
