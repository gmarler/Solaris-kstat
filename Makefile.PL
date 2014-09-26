use 5.008005;
use ExtUtils::MakeMaker;
WriteMakefile(
  NAME           => 'Solaris::kstat',
  VERSION_FROM   => 'lib/Solaris/kstat.pm',
  PREREQ_PM      => { 'Test::Most' => 0 },
  ABSTRACT_FROM  => 'lib/Solaris/kstat.pm',
  AUTHOR         => 'Gordon Marler',
  LIBS           => [''],
  DEFINE         => '',
  INC            => '-I.',
  OBJECT         => '$(O_FILES)',
);
