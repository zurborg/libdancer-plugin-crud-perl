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

    resource foo =>
        rules => {
            generic => {
                checks => [
                    foo_id => [ Validate::Tiny::is_in([qw[ 123 ]]) ]
                ]
            },
            update => {
                fields => [qw[ name ]],
                checks => [
                    name => [ Validate::Tiny::is_required, Validate::Tiny::is_like(qr{^[a-z]{3}$}) ]
                ]
            }
        },
        read => sub {
            return var('validate')->data;
        },
        update => sub {
            return var('validate')->data;
        },
        prefix_id => sub {
            resource bar =>
                rules => {
                    generic => {
                        checks => [
                            bar_id => [ Validate::Tiny::is_in([qw[ 456 ]]) ]
                        ]
                    },
                    update => {
                        fields => [qw[ name ]],
                        checks => [
                            name => [ Validate::Tiny::is_required, Validate::Tiny::is_like(qr{^[a-z]{5}$}) ]
                        ]
                    }
                },
                read => sub {
                    return var('validate')->data;
                },
                update => sub {
                    return var('validate')->data;
                };
        };
}

use Dancer::Test;
use Data::Dumper;

#plan tests => 9;

my $r;

$r = dancer_response(GET => '/foo/123');
is_deeply $r->{content}, { foo_id => 123 };

$r = dancer_response(GET => '/foo/456');
is_deeply $r->{content}, { error => { foo_id => 'Invalid value' } };

$r = dancer_response(PUT => '/foo/123', { params => { name => 'xxx' } });
is_deeply $r->{content}, { foo_id => 123, name => 'xxx' };

$r = dancer_response(PUT => '/foo/123', { params => { name => 'XXX' } });
is_deeply $r->{content}, { error => { name => 'Invalid value' } };

$r = dancer_response(GET => '/foo/123/bar/456');
is_deeply $r->{content}, { foo_id => 123, bar_id => 456 };

$r = dancer_response(GET => '/foo/456/bar/456');
is_deeply $r->{content}, { error => { foo_id => 'Invalid value' } };

$r = dancer_response(GET => '/foo/456/bar/123');
is_deeply $r->{content}, { error => { foo_id => 'Invalid value', bar_id => 'Invalid value' } };

$r = dancer_response(PUT => '/foo/123/bar/456', { params => { name => 'xxxxx' } });
is_deeply $r->{content}, { foo_id => 123, bar_id => 456, name => 'xxxxx' };

$r = dancer_response(PUT => '/foo/123/bar/456', { params => { name => 'XXXXX' } });
is_deeply $r->{content}, { error => { name => 'Invalid value' } };

$r = dancer_response(GET => '/foo/123', { params => { garbage => '???' } });
is_deeply $r->{content}, { foo_id => 123 };

done_testing;
