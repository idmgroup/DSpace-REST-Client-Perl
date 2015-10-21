#!perl -w
use strict;
use Test::More;

my @modules = qw(
    DSpace::REST::Client
);

my @programs = qw(
);

plan tests => @modules + @programs;

# try to load all modules
foreach my $module (@modules) {
    use_ok( $module );
}

# try to load the programs, which should at this stage be in blib/
for my $program (@programs) {
    require_ok( catfile(rel2abs('.'), 'blib', 'script', $program) );
}
