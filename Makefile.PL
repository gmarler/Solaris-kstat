use 5.008005;
use ExtUtils::MakeMaker;
WriteMakefile(
  NAME           => 'Solaris::kstat',
  VERSION_FROM   => 'lib/Solaris/kstat.pm',
  PREREQ_PM      => { 'Test::Most' => 0,
                      'Exporter' => '5.57', },
  ABSTRACT_FROM  => 'lib/Solaris/kstat.pm',
  AUTHOR         => 'Gordon Marler',
  LIBS           => ['-lkstat'],
  DEFINE         => '-DKSTAT_DEBUG -DUSE_64_BIT_INT',
  INC            => '-I.',
  # CFLAGS         => '-xdumpmacros',
  OBJECT         => '$(O_FILES)',
);
