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

sub test_collections {
    my $community = {
        name => $FULL_TEST_COMMUNITY_NAME
    };
    my $result_com = $dspace->create_community(entity => $community,
        headers => get_headers('application/json', 'application/json'));
    my $com_id = $result_com->{id};

    my $collection = {
        name => TEST_COLLECTION_NAME
    };
    my $result_col = $dspace->add_community_collection(community_id => $com_id, entity => $collection,
        headers => get_headers('application/json', 'application/json'));
    ok(defined $result_col, 'created collection');
    ok(defined $result_col->{id}, 'created collection ID');
    ok($result_col->{id} > 0, 'created collection ID > 0');
    ok($result_col->{handle} =~ m,^[0-9]+/[0-9]+$,, 'created collection handle');
    my $col_id = $result_col->{id};

    $result_col = $dspace->get_collection(collection_id => $col_id,
        headers => get_headers(undef, 'application/json'));
    ok($result_col->{id} eq $col_id, 'get collection ID');
    ok($result_col->{name} eq TEST_COLLECTION_NAME, 'get collection name');

    $result_col->{copyrightText} = 'Copyright for pictures with unicode '.TEST_UNICODE;
    $result_col->{introductoryText} = 'An introductory text for pictures with unicode '.TEST_UNICODE;
    $result_col->{shortDescription} = 'A short description for Arno::db pictures with unicode '.TEST_UNICODE;
    $result_col->{sidebarText} = 'Sidebar text for pictures with unicode '.TEST_UNICODE;
    $dspace->update_collection(collection_id => $col_id, entity => $result_col,
        headers => get_headers('application/json', 'application/json'));

    $result_col = $dspace->get_collection(collection_id => $col_id,
        headers => get_headers(undef, 'application/json'));
    ok($result_col->{id} eq $col_id, 'get2 collection ID');
    ok($result_col->{name} eq TEST_COLLECTION_NAME, 'get2 collection name');
    ok($result_col->{copyrightText} eq 'Copyright for pictures with unicode '.TEST_UNICODE, 'get2 collection copyright');
    ok($result_col->{introductoryText} eq 'An introductory text for pictures with unicode '.TEST_UNICODE, 'get2 collection introduction');
    ok($result_col->{shortDescription} eq 'A short description for Arno::db pictures with unicode '.TEST_UNICODE, 'get2 collection description');
    ok($result_col->{sidebarText} eq 'Sidebar text for pictures with unicode '.TEST_UNICODE, 'get2 collection sidebar');

    $dspace->delete_collection(collection_id => $col_id);
    eval {
        $result_col = $dspace->get_collection(collection_id => $col_id,
            headers => get_headers(undef, 'application/json'));
    };
    ok($@ && ($@ =~ m/^Resource not found /), 'deleted collection');
    $dspace->delete_community(community_id => $com_id);
}

$dspace->login(
    entity => {
        email => DEMO_DSPACE_ADMIN,
        password => DEMO_DSPACE_PASSWORD
    },
    headers => get_headers('application/json')
);

clean();

test_collections();

#$dspace->logout();

done_testing();

