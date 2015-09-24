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

$k->copy();

done_testing();
