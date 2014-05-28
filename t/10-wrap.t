use strict;
use warnings;
use Dancer::ModuleLoader;
use Test::More import => ['!pass'];
use Try::Tiny;

# Dancer::Test had a bug in version previous 1.3059_01 that prevent this test
# from running correctly.
my $dancer_version = eval "\$Dancer::VERSION";
$dancer_version =~ s/_//g;
plan skip_all => "Dancer 1.3059_01 is needed for this test (you have $dancer_version)"
  if $dancer_version < 1.305901;

try {
    require Validate::Tiny;
} catch {
    plan skip_all => "Validate::Tiny is needed for this test";
};

#plan tests => 1;

{
    package Webservice;
    use Dancer;
    use Dancer::Plugin::CRUD;
    use Test::More import => ['!pass'];
    
    set serialzier => 'JSON';
    
    sub is_def {
        return sub { defined(shift) ? undef : 'Not defined' }
    }

    resource foo =>
        validation => {
            generic => {
                checks => [
                    foo_id => is_def,
                    foo_id => Validate::Tiny::is_in([qw[ 123 ]])
                ]
            },
        },
        prefix_id => sub {
			wrap GET    => get    => sub { return var('validate')->data };
			wrap POST   => post   => sub { return var('validate')->data };
			wrap PUT    => put    => sub { return var('validate')->data };
			wrap DELETE => delete => sub { return var('validate')->data };
			wrap PATCH  => patch  => sub { return var('validate')->data };
        };
}

use Dancer::Test;
use Data::Dumper;

plan tests => 5;

my $r;

$r = dancer_response(GET => '/foo/123/get');
is_deeply $r->{content}, { foo_id => 123 }, 'get foo->get ok';

$r = dancer_response(POST => '/foo/123/post');
is_deeply $r->{content}, { foo_id => 123 }, 'post foo->post ok';

$r = dancer_response(PUT => '/foo/123/put');
is_deeply $r->{content}, { foo_id => 123 }, 'put foo->put ok';

$r = dancer_response(DELETE => '/foo/123/delete');
is_deeply $r->{content}, { foo_id => 123 }, 'delete foo->delete ok';

$r = dancer_response(PATCH => '/foo/123/patch');
is_deeply $r->{content}, { foo_id => 123 }, 'patch foo->patch ok';

diag sprintf "[%s] %s", $_->{level}, $_->{message} for @{read_logs()};

done_testing;
