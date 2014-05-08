use strict;
use warnings;
use ExtUtils::MakeMaker 6.3002;
use Hash::Merge::Simple;
our %BuildOptions;
require "config/BuildOptions.pm";
sub addopt(%) {
    local %_ = @_;
    %BuildOptions = %{ Hash::Merge::Simple->merge(\%BuildOptions, \%_) };
}
require "config/DevelopmentOptions.pm";
WriteMakefile(%BuildOptions);
