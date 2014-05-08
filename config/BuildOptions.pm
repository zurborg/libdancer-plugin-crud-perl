%BuildOptions = (%BuildOptions,
    NAME                => 'Dancer::Plugin::CRUD',
    DISTNAME            => 'Dancer-Plugin-CRUD',
    AUTHOR              => 'David Zurborg <zurborg@cpan.org>',
    VERSION_FROM        => 'lib/Dancer/Plugin/CRUD.pm',
    ABSTRACT_FROM       => 'lib/Dancer/Plugin/CRUD.pm',
    LICENSE             => 'perl',
    PL_FILES            => {},
    PMLIBDIRS           => [qw[ lib ]],
    PREREQ_PM => {
        'Test::More' => 0,
    },
    dist => {
        COMPRESS            => 'gzip -9f',
        SUFFIX              => 'gz',
        CI                  => 'git add',
        RCS_LABEL           => 'true',
    },
    clean               => { FILES => 'Dancer-Plugin-CRUD-*' },
    depend => {
	'$(FIRST_MAKEFILE)' => 'config/BuildOptions.pm',
    },
);
