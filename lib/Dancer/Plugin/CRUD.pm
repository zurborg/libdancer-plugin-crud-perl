package Dancer::Plugin::CRUD;

use Modern::Perl;

=head1 NAME

Dancer::Plugin::CRUD - A plugin for writing RESTful apps with Dancer

=head1 VERSION

Version 1.01

=cut

our $VERSION = 1.01;

=head1 DESCRIPTION

This plugin is derived from L<Dancer::Plugin::REST|Dancer::Plugin::REST> and helps you write a RESTful webservice with Dancer.

=head1 SYNOPSYS

    package MyWebService;

    use Dancer;
    use Dancer::Plugin::CRUD;

    prepare_serializer_for_format;

    read '/user/:id.:format' => sub {
        User->find(params->{id});
    };

    # curl http://mywebservice/user/42.json
    { "id": 42, "name": "John Foo", email: "john.foo@example.com"}

    # curl http://mywebservice/user/42.yml
    --
    id: 42
    name: "John Foo"
    email: "john.foo@example.com"

=cut

use Carp 'croak';
use Dancer ':syntax';
use Dancer::Plugin;
use Sub::Name;
use Text::Pluralize;

our $SUFFIX = '_id';

my $content_types = {
	json => 'application/json',
	yml  => 'text/x-yaml',
	xml  => 'application/xml',
};

my %triggers_map = (
    index  => \&get,
    read   => \&get,
    update => \&put,
    create => \&post,
    delete => \&del,
);

my %http_codes = (

    # 1xx
    100 => 'Continue',
    101 => 'Switching Protocols',
    102 => 'Processing',

    # 2xx
    200 => 'OK',
    201 => 'Created',
    202 => 'Accepted',
    203 => 'Non-Authoritative Information',
    204 => 'No Content',
    205 => 'Reset Content',
    206 => 'Partial Content',
    207 => 'Multi-Status',
    210 => 'Content Different',

    # 3xx
    300 => 'Multiple Choices',
    301 => 'Moved Permanently',
    302 => 'Found',
    303 => 'See Other',
    304 => 'Not Modified',
    305 => 'Use Proxy',
    307 => 'Temporary Redirect',
    310 => 'Too many Redirect',

    # 4xx
    400 => 'Bad Request',
    401 => 'Unauthorized',
    402 => 'Payment Required',
    403 => 'Forbidden',
    404 => 'Not Found',
    405 => 'Method Not Allowed',
    406 => 'Not Acceptable',
    407 => 'Proxy Authentication Required',
    408 => 'Request Time-out',
    409 => 'Conflict',
    410 => 'Gone',
    411 => 'Length Required',
    412 => 'Precondition Failed',
    413 => 'Request Entity Too Large',
    414 => 'Request-URI Too Long',
    415 => 'Unsupported Media Type',
    416 => 'Requested range unsatisfiable',
    417 => 'Expectation failed',
    418 => 'Teapot',
    422 => 'Unprocessable entity',
    423 => 'Locked',
    424 => 'Method failure',
    425 => 'Unordered Collection',
    426 => 'Upgrade Required',
    449 => 'Retry With',
    450 => 'Parental Controls',

    # 5xx
    500 => 'Internal Server Error',
    501 => 'Not Implemented',
    502 => 'Bad Gateway',
    503 => 'Service Unavailable',
    504 => 'Gateway Time-out',
    505 => 'HTTP Version not supported',
    507 => 'Insufficient storage',
    509 => 'Bandwidth Limit Exceeded',
);

our @respath;
our $default_serializer;
our $validation_rules = {};

sub _generate_sub($) {
	my %options = %{ shift() };
	
	my $resname = @{ $options{curpath} }[-1];
	my $rules = [ map { $validation_rules->{$_}->{generic} } grep { exists $validation_rules->{$_} } reverse @{ $options{curpath} } ];
	if (@$rules > 0) {
		push @$rules, $validation_rules->{$resname}->{$options{action}}
			if exists $validation_rules->{$resname}->{$options{action}};
			
		$rules = {
			fields  => [ map { ( @{ $_->{fields}  } ) } grep { exists $_->{fields}  } @$rules ],
			checks  => [ map { ( @{ $_->{checks}  } ) } grep { exists $_->{checks}  } @$rules ],
			filters => [ map { ( @{ $_->{filters} } ) } grep { exists $_->{filters} } @$rules ],
		};
	} else {
		$rules = undef;
	}
	
	my @idfields = map { $_.$SUFFIX } @{ $options{curpath} };
	
	my $subname = join('_', $resname, $options{action});
	
	return subname($subname, sub {
		if (defined $rules) {
			use Validate::Tiny ();
			my $result = Validate::Tiny->new(scalar params, {
				%$rules,
				fields => [
					@idfields,
					@{ $rules->{fields} }
				]
			});
			unless ($result->success) {
				status(400);
				return { error => $result->error };
			}
			var validate => $result;
		}
		
		my @ret = $options{coderef}->(@{ $options{curpath} });
		
		if (@ret and ref $ret[0] eq '' and $ret[0] =~ m{^\d{3}$}) {
			# return ($http_status_code, ...)
			if ($ret[0] >= 400) {
				# return ($http_error_code, $error_message)
				status($ret[0]);
				return { error => $ret[1] };
			} else {
				# return ($http_success_code, $payload)
				status($ret[0]);
				return $ret[1];
			}
		} elsif (status eq '200') {
			# http status wasn't changed yet
			given ($options{action}) {
				when ('create') { status(201); }
				when ('update') { status(202); }
				when ('delete') { status(202); }
			}
		}
		# return payload
		return (wantarray ? @ret : $ret[0]);
	});
}

=head1 METHODS

=head2 C<< prepare_serializer_for_format >>

When this pragma is used, a before filter is set by the plugin to automatically
change the serializer when a format is detected in the URI.

That means that each route you define with a B<:format> token will trigger a
serializer definition, if the format is known.

This lets you define all the REST actions you like as regular Dancer route
handlers, without explicitly handling the outgoing data format.

=cut

register prepare_serializer_for_format => sub () {
	my $conf        = plugin_setting;
	my $serializers = {
		'json' => 'JSON',
		'yml'  => 'YAML',
		'xml'  => 'XML',
		'dump' => 'Dumper',
		(exists $conf->{serializers} ? %{$conf->{serializers}} : ())
	};

    hook(before => sub {
        # remember what was there before
        $default_serializer ||= setting('serializer');

        my $format = param('format') or return;

        my $serializer = $serializers->{$format} or return halt(Dancer::Error->new(
			code    => 404,
			title   => "unsupported format requested",
			message => "unsupported format requested: " . $format
		)->render);

        set(serializer => $serializer);

        # check if we were supposed to deserialize the request
        Dancer::Serializer->process_request(Dancer::SharedData->request);

        content_type($content_types->{$format} || setting('content_type'));
    });

    hook(after => sub {
        # put it back the way it was
        set(serializer => $default_serializer);
    });
};

=head2 C<< resource >>

This keyword lets you declare a resource your application will handle.

Derived from L<Dancer::Plugin::REST|Dancer::Plugin::REST>, this method has rewritten to provide a more slightly convention. C<get> has been renamed to C<read> and three new actions has been added: C<index>, C<prefix> and C<prefix_id>

Also, L<Text::Pluralize|Text::Pluralize> is applied to resource name with count=1 for singular variant and count=2 for plural variant. If you don't provide a singular/plural variant (i.e. resource name contains parenthesis) the singular and the plural becomes same.

The id name is derived from singular resource name, appended with C<_id>.

    resource 'user(s)' =>
        index  => sub { ... }, # return all users
        read   => sub { ... }, # return user where id = params->{user_id}
        create => sub { ... }, # create a new user with params->{user}
        delete => sub { ... }, # delete user where id = params->{user_id}
        update => sub { ... }, # update user with params->{user}
        prefix => sub {
          # prefixed resource in plural
          read '/foo' => sub { ... },
        },
        prefix_id => sub {
          # prefixed resource in singular with id
		  # params->{user_id}
          read '/bar' => sub { ... },
        };

    # this defines the following routes:
    # prefix_id =>
    #   GET /user/:user_id/bar
    # prefix =>
    #   GET /users/foo
    # read =>
    #   GET /user/:id.:format
    #   GET /user/:id
    # index =>
    #   GET /users.:format
    #   GET /users
    # create =>
    #   POST /user.:format
    #   POST /user
    # delete =>
    #   DELETE /user/:id.:format
    #   DELETE /user/:id
    # update =>
    #   PUT /user/:id.:format
    #   PUT /user/:id

The routes are created in the above order.

Hint: resources can be stacked with C<prefix>/C<prefix_id>:

	resource foo =>
		prefix => sub {
			get '/bar' => sub {
				return 'Hi!'
			};
		}, # GET /foo/bar
		prefix_id => sub {
			get '/bar' => sub {
				return 'Hey '.param('foo_id')
			}; # GET /foo/123/bar
			resource bar =>
				read => sub {
					return 'foo is '
						. param('foo_id')
						.' and bar is '
						. param('bar_id')
					}
				}; # GET /foo/123/bar/456
		};

When is return value is a HTTP status code (three digits), C<status(...)> is applied to it. A second return value may be the value to be returned to the client itself:

	sub {
		return 200
	};
	
	sub {
		return 404 => 'This object has not been found.'
	}
	
	sub {
		return 201 => { ... }
	};
	
The default HTTP status code ("200 OK") differs in some actions: C<create> response with "201 Created", C<delete> and C<update> response with "202 Accepted".

=head3 Change of suffix

The appended suffix, C<_id> for default, can be changed by setting C<< $Dancer::Plugin::CRUD::SUFFIX >>. This affects both parameter names and the suffix of parameterized C<prefix> method:

	$Dancer::Plugin::CRUD::SUFFIX = 'Id';
	resource 'User' => prefixId => sub { return param('UserId') };

=cut

register(resource => sub ($%) {
    my $resource = my $resource1 = my $resource2 = shift;
    my %triggers = @_;
    
    {
        my $c = quotemeta '()|{}';
        if ($resource =~ m{[$c]}) {
            $resource1 = pluralize($resource1, 1);
            $resource2 = pluralize($resource2, 2);
        }
    }
    
    push @respath => $resource1;
    my @curpath = (@respath);
	
	if (exists $triggers{validation}) {
		$validation_rules->{$resource1} = delete $triggers{validation};
	}
    
    if (exists $triggers{'prefix'.$SUFFIX}) {
        prefix("/${resource1}/:${resource1}".$SUFFIX ,=> $triggers{'prefix'.$SUFFIX});
        delete $triggers{'prefix'.$SUFFIX};
    }

    if (exists $triggers{prefix}) {
        prefix("/${resource2}" => $triggers{prefix});
        delete $triggers{prefix};
    }

    foreach my $action (qw(read index create delete update)) {
        next unless exists $triggers{$action};

		my $route;
		
		given ($action) {
        	when ('index') {
				$route = "/${resource2}";
			}
			when ('create') {
				$route = "/${resource1}";
			}
			default {
				$route = "/${resource1}/:${resource1}".$SUFFIX;
			}
        }
		
		my $sub = _generate_sub({
			action => $action,
			curpath => [ @respath ],
			coderef => $triggers{$action}
		});

		$triggers_map{$action}->($_ => $sub) foreach ($route.'.:format', $route);
    }
    
    pop @respath;
});

=head2 helpers

Some helpers are available. This helper will set an appropriate HTTP status for you.

=head3 status_ok

    status_ok({users => {...}});

Set the HTTP status to 200

=head3 status_created

    status_created({users => {...}});

Set the HTTP status to 201

=head3 status_accepted

    status_accepted({users => {...}});

Set the HTTP status to 202

=head3 status_bad_request

    status_bad_request("user foo can't be found");

Set the HTTP status to 400. This function as for argument a scalar that will be used under the key B<error>.

=head3 status_not_found

    status_not_found("users doesn't exists");

Set the HTTP status to 404. This function as for argument a scalar that will be used under the key B<error>.

=cut

register send_entity => sub {
    # entity, status_code
    status($_[1] || 200);
    $_[0];
};

for my $code (keys %http_codes) {
    my $helper_name = lc($http_codes{$code});
    $helper_name =~ s/[^\w]+/_/gms;
    $helper_name = "status_${helper_name}";

    register $helper_name => sub {
        if ($code >= 400) {
            send_entity({error => $_[0]}, $code);
        }
        else {
            send_entity($_[0], $code);
        }
    };
}

=head1 LICENCE

This module is released under the same terms as Perl itself.

=head1 AUTHORS

This module has been rewritten by David Zurborg C<< <zurborg@cpan.org> >>, based on code written by Alexis Sukrieh C<< <sukria@sukria.net> >> and Franck Cuny.

=head1 SEE ALSO

L<Dancer>
L<http://en.wikipedia.org/wiki/Representational_State_Transfer>
L<Dancer::Plugin::REST>
L<Text::Pluralize>

=head1 AUTHORS

=over 4

=item *

David Zurborg <zurborg@cpan.org>

=item *

Alexis Sukrieh <sukria@sukria.net> (Author of Dancer::Plugin::REST)

=item *

Franck Cuny <franckc@cpan.org> (Author of Dancer::Plugin::REST)

=back

=head1 BUGS

Please report any bugs or feature requests trough my project management tool
at L<http://development.david-zurb.org/projects/libdancer-plugin-crud-perl/issues/new>. I
will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Dancer::Plugin::CRUD

You can also look for information at:

=over 4

=item * Redmine: Homepage of this module

L<http://development.david-zurb.org/projects/libdancer-plugin-crud-perl>

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Dancer-Plugin-CRUD>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Dancer-Plugin-CRUD>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/[Dancer-Plugin-CRUD>

=item * Search CPAN

L<http://search.cpan.org/dist/Dancer-Plugin-CRUD/>

=back

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by David Zurborg <zurborg@cpan.org>.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

register_plugin;
1;
