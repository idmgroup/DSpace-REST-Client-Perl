#!perl -w
use Modern::Perl;
use Test::More;

# make sure we can load what we need
BEGIN {
	use_ok('DSpace::REST');
}

use constant {
    DEMO_DSPACE_ADMIN => 'dspacedemo+admin@gmail.com',
    DEMO_DSPACE_PASSWORD => 'dspace',
    DEMO_DSPACE_URL => 'https://demo.dspace.org/rest',
};

sub configure_client {
    my $dspace = shift;
    $dspace->client->setTimeout(72000);
    my $ua = $dspace->client->getUseragent();
    $ua->ssl_opts(SSL_fingerprint => 'sha256$9d9f9e072e4edfd6b0a16f87229f2634cc0c480d201272c0ba7b8a0b7defacad');
}

sub test_client {
    my $dspace = shift;

    # index
    my $index = $dspace->say_html_hello();
    ok(index($index, '<title>DSpace REST - index</title>') >= 0, 'index title');
    ok(index($index, '<h2>Index</h2>') >= 0, 'index index heading');
    ok(index($index, '<h2>Communities</h2>') >= 0, 'index communities heading');
    ok(index($index, '<h2>Collections</h2>') >= 0, 'index collections heading');
    ok(index($index, '<h2>Items</h2>') >= 0, 'index items heading');
    ok(index($index, '<h2>Bitstreams</h2>') >= 0, 'index bitstreams heading');

    # test
    my $str = $dspace->test();
    ok($str eq 'REST api is running.', 'test string');
}

{
    my $dspace = DSpace::REST->new(
        'host' => DEMO_DSPACE_URL
    );
    configure_client($dspace);
    test_client($dspace);
}

{
    my $dspace5 = DSpace::REST->new(
        'dspace_version' => 5.99,
        'host' => DEMO_DSPACE_URL
    );
    configure_client($dspace5);
    test_client($dspace5);
}

eval
{
    my $dspace6 = DSpace::REST->new(
        'dspace_version' => 6.0,
        'host' => DEMO_DSPACE_URL
    );
    configure_client($dspace6);
    test_client($dspace6);
};
# TODO get the WADL from a v6 and generate ClientV6.pm.
ok($@ && $@ =~ m/^Version 6 of DSpace REST API not supported yet/, 'v6 not supported');

done_testing();

