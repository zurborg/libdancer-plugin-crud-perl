addopt(
    postamble => {
        REDMINE_BASEURL     => 'http://development.david-zurb.org/',
        REDMINE_PROJECT     => 'libdancer-plugin-crud-perl',
        README_SECTIONS     => [ 'NAME', 'VERSION', 'DESCRIPTION', 'AUTHOR', 'SUPPORT', 'COPYRIGHT & LICENSE' ],
    },
    depend => {
        '$(FIRST_MAKEFILE)' => 'config/BuildOptions.pm config/DevelopmentOptions.pm',
    },
);

sub extend_makefile {
	
	my $out;
	
	while (@_) {
		my $target = shift;
		$out .= "$target :: ";
		my %opts = %{ shift() };
		if (exists $opts{preq}) {
			$out .= join ' ' => @{ $opts{preq} };
		}
		$out .= "\n";
		if (exists $opts{cmds}) {
			$out .= join "\n" => map { "\t$_" } @{ $opts{cmds} };
		}
		$out .= "\n\n";
	}
	
	return $out;
}

sub MY::postamble {
	my ($MM, %options) = @_;
	return main::extend_makefile(
		redmine_wiki => {
			preq => [qw[ $(MAN1PODS) $(MAN3PODS) ]],
			cmds => [
				sprintf 'pods2redmine --base-url "%s" --project "%s" --version "%s" --with-toc -- $?'
				,$options{REDMINE_BASEURL}
				,$options{REDMINE_PROJECT}
				,$MM->{VERSION}
			]
		},
		'documentation/README.pod' => {
			preq => [ $MM->{ABSTRACT_FROM} ],
			cmds => [
				'podselect '.join(' ' => map { "-section '$_'" } @{ $options{README_SECTIONS} }).' -- "$<" > "$@"'
			]
		},
		README => {
			preq => [qw[ documentation/README.pod ]],
			cmds => [
				'pod2readme "$<" "$@" README'
			]
		},
		INSTALL => {
			preq => [qw[ documentation/INSTALL.pod ]],
			cmds => [
				'pod2readme "$<" "$@" README'
			]
		},
		documentation => {
			preq => [qw[ README INSTALL ]],
		},
		'all' => {
			preq => [qw[ documentation MANIFEST.SKIP ]]
		},
		'MANIFEST.SKIP' => {
			preq => [qw[ MANIFEST.IGNORE ]],
			cmds => [
			    'echo "#!include_default" > "$@" ',
			    'for file in $?; do echo "#!include $$file" >> "$@"; done',
			    '$(MAKE) skipcheck',
			]
		},
	);
}