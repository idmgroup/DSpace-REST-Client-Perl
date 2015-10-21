#!perl -w
use Modern::Perl;
use Test::More;

# make sure we can load what we need
BEGIN {
	use_ok('DSpace::REST::Client');
}

use constant {
    DEMO_DSPACE_ADMIN => 'dspacedemo+admin@gmail.com',
    DEMO_DSPACE_BAD_PASSWORD => 'DSP4CE',
    DEMO_DSPACE_PASSWORD => 'dspace',
    DEMO_DSPACE_URL => 'https://demo.dspace.org/rest',
    TEST_COLLECTION_NAME => "Arno::db pictures",
    _TEST_COMMUNITY_NAME => "Arno::db test"
};

my $hostname = `hostname`;
chomp($hostname);
my $FULL_TEST_COMMUNITY_NAME = _TEST_COMMUNITY_NAME."($], $hostname)";

my $dspace = DSpace::REST::Client->new(
    'host' => DEMO_DSPACE_URL
);

# Miscellaneous client calls
$dspace->client->setTimeout(72000);
my $ua = $dspace->client->getUseragent();
$ua->ssl_opts(SSL_fingerprint => 'sha256$9d9f9e072e4edfd6b0a16f87229f2634cc0c480d201272c0ba7b8a0b7defacad');

sub get_headers {
    my ($request_type, $response_type) = @_;
    my %headers;
    $headers{'Content-Type'} = $request_type if (defined $request_type);
    $headers{'Accept'} = $response_type if (defined $response_type);
    \%headers;
}

sub test_index {
    # index
    my $index = $dspace->say_html_hello();
    ok(index($index, '<title>DSpace REST - index</title>') >= 0, 'index title');
    ok(index($index, '<h2>Index</h2>') >= 0, 'index index heading');
    ok(index($index, '<h2>Communities</h2>') >= 0, 'index communities heading');
    ok(index($index, '<h2>Collections</h2>') >= 0, 'index collections heading');
    ok(index($index, '<h2>Items</h2>') >= 0, 'index items heading');
    ok(index($index, '<h2>Bitstreams</h2>') >= 0, 'index bitstreams heading');

    # login
    my $token = $dspace->login(
        entity => {
            email => DEMO_DSPACE_ADMIN,
            password => DEMO_DSPACE_PASSWORD
        },
        headers => get_headers('application/json')
    );
    ok($token =~ m/^[-0-9A-Fa-f]+$/, "dspace token format");

# Don't test the logout as it is a global logout
if (0) {
    # logout
    $dspace->logout();
    eval {
        $dspace->logout();
    };
    ok($@ && ($@ =~ m/ 400 /), 'second logout failure');
}

    # test
    my $str = $dspace->test();
    ok($str eq 'REST api is running.', 'test string');
}

test_index();

done_testing();

