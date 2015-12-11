#!perl -w
use Modern::Perl;
use Test::More;

# make sure we can load what we need
BEGIN {
	use_ok('DSpace::REST');
}

use constant {
    DEMO_DSPACE_ADMIN => 'dspacedemo+admin@gmail.com',
    DEMO_DSPACE_BAD_PASSWORD => 'DSP4CE',
    DEMO_DSPACE_PASSWORD => 'dspace',
    DEMO_DSPACE_URL => 'https://demo.dspace.org/rest',
    TEST_COLLECTION_NAME => "Arno::db pictures",
    _TEST_COMMUNITY_NAME => "Arno::db test",
    TEST_UNICODE => "\x{6211}\x{662f}\x{4e2d}\x{56fd}\x{4eba}",
};

my $hostname = `hostname`;
chomp($hostname);
my $FULL_TEST_COMMUNITY_NAME = _TEST_COMMUNITY_NAME."($], $hostname)";

my $dspace = DSpace::REST->new(
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

sub clean {
    cleanCommunitiesByName($FULL_TEST_COMMUNITY_NAME);
}

sub cleanCommunitiesByName {
    my $name = shift;
    return if(!$name || $name eq '');
    my $offset = 0;
    while (1) {
        my $slice = $dspace->get_communities(limit => 20, offset => $offset,
            headers => get_headers(undef, 'application/json'));
        if (defined $slice && @$slice > 0) {
            foreach my $com (@$slice) {
                if ($com->{name} eq $name) {
                    $dspace->delete_community(community_id => $com->{id});
                } else {
                    ++$offset;
                }
            }
        } else {
            last;
        }
    }
}

sub test_communities {
    my $community = {
        name => $FULL_TEST_COMMUNITY_NAME
    };
    my $result = $dspace->create_community(entity => $community,
        headers => get_headers('application/json', 'application/json'));
    ok(defined $result, 'created community');
    ok(defined $result->{id}, 'created community ID');
    ok($result->{id} > 0, 'created community ID > 0');
    ok($result->{handle} =~ m,^[0-9]+/[0-9]+$,, 'created community handle');
    my $com_id = $result->{id};

    $result = $dspace->get_community(community_id => $com_id,
        headers => get_headers(undef, 'application/json'));
    ok($result->{id} eq $com_id, 'get community ID');
    ok($result->{name} eq $FULL_TEST_COMMUNITY_NAME, 'get community name');

    $result->{copyrightText} = 'Copyright with unicode '.TEST_UNICODE;
    $result->{introductoryText} = 'An introductory text with unicode '.TEST_UNICODE;
    $result->{shortDescription} = 'A short description for Arno::db with unicode '.TEST_UNICODE;
    $result->{sidebarText} = 'Sidebar text with unicode '.TEST_UNICODE;
    $dspace->update_community(community_id => $com_id, entity => $result,
        headers => get_headers('application/json', 'application/json'));

    $result = $dspace->get_community(community_id => $com_id,
        headers => get_headers(undef, 'application/json'));
    ok($result->{id} eq $com_id, 'get2 community ID');
    ok($result->{name} eq $FULL_TEST_COMMUNITY_NAME, 'get2 community name');
    ok($result->{copyrightText} eq 'Copyright with unicode '.TEST_UNICODE, 'get2 community copyright');
    ok($result->{introductoryText} eq 'An introductory text with unicode '.TEST_UNICODE, 'get2 community introduction');
    ok($result->{shortDescription} eq 'A short description for Arno::db with unicode '.TEST_UNICODE, 'get2 community description');
    ok($result->{sidebarText} eq 'Sidebar text with unicode '.TEST_UNICODE, 'get2 community sidebar');

    $dspace->delete_community(community_id => $com_id);
    eval {
        $result = $dspace->get_community(community_id => $com_id,
            headers => get_headers(undef, 'application/json'));
    };
    ok($@ && ($@ =~ m/^Resource not found /), 'deleted community');
}

$dspace->login(
    entity => {
        email => DEMO_DSPACE_ADMIN,
        password => DEMO_DSPACE_PASSWORD
    },
    headers => get_headers('application/json')
);

#clean();

test_communities();

#$dspace->logout();

done_testing();

