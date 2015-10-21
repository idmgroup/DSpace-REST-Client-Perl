#!perl -T
use strict;
use Test::More skip_all => 'TODO: write proper documentation';
plan skip_all => "Test::Pod::Coverage 1.04 required for testing POD coverage"
    unless eval "use Test::Pod::Coverage 1.04; 1";
foreach my $module (
					 all_modules()
				   ) {
	pod_coverage_ok( $module,
				   );
}
done_testing();
