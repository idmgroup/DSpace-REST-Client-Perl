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

sub read_bin {
    my $infile = shift;
    # Yes, this is bogus
    my $size = 100000;
    open(my $INFILE, "<", $infile) or die "Not able to open $infile.";
    binmode($INFILE);
    my $data;
    read($INFILE, $data, $size);
    close($INFILE);
    return $data;
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
                }
            }
        } else {
            last;
        }
        $offset += 20;
    }
}

sub create_bitstream {
    my ($item_id, $res_name) = @_;
    my $base_name = $res_name;
    $base_name =~ s,^.*/([^/]+)$,$1,g;
    my $content = read_bin("t/resources/$res_name");
    my $bitstream = $dspace->add_item_bitstream(item_id => $item_id, name => $base_name, year => 2015, month => 2, day => 17, entity => $content,
        headers => get_headers(undef, 'application/json'));
    ok($bitstream->{name} eq $base_name, 'created bitstream name');
    ok($bitstream->{bundleName} eq 'ORIGINAL', 'created bitstream bundle');
    ok($bitstream->{format} eq 'image/png', 'created bitstream format');
    return $bitstream;
}

sub test_items {
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
    my $col_id = $result_col->{id};

    my $item = {
        name => 'Logo IDM'
    };
    my $result_item = $dspace->add_collection_item(collection_id => $col_id, entity => $item,
        headers => get_headers('application/json', 'application/json'));
    ok(defined $result_item, 'created item');
    ok(defined $result_item->{id}, 'created item ID');
    ok($result_item->{id} > 0, 'created item ID > 0');
    ok($result_item->{handle} =~ m,^[0-9]+/[0-9]+$,, 'created item handle');
    my $item_id = $result_item->{id};

    $result_item = $dspace->get_item(item_id => $item_id,
        headers => get_headers(undef, 'application/json'));
    ok($result_item->{id} eq $item_id, 'get item ID');
    # XXX Well, I think I spotted a bug in DSpace REST API.
    ok(!defined $result_item->{name}, 'get item name');

    my $bitstream;
    $bitstream = create_bitstream($item_id, "com/idmgroup/brand/logo-idm_big_transparent_hd.png");
    $bitstream = create_bitstream($item_id, "com/idmgroup/brand/logo-idm_small_transparent_hd.png");
    $bitstream = create_bitstream($item_id, "com/idmgroup/brand/logo-idm_big_vertical_hd.png");
    $bitstream = create_bitstream($item_id, "com/idmgroup/brand/logo-idm_small_vertical_hd.png");
    my $bs_id = $bitstream->{id};
    $bitstream = $dspace->get_bitstream(bitstream_id => $bs_id,
        headers => get_headers(undef, 'application/json'));
    ok($bitstream->{id} == $bs_id, 'get bitstream ID');
    ok($bitstream->{name} eq 'logo-idm_small_vertical_hd.png', 'get bitstream name');

    $dspace->delete_bitstream(bitstream_id => $bs_id);
    eval {
        $bitstream = $dspace->get_bitstream(bitstream_id => $bs_id,
            headers => get_headers(undef, 'application/json'));
    };
    ok($@ && ($@ =~ m/^Resource not found /), 'deleted bitstream');
    # The other bitstreams will be deleted with the item.
    $dspace->delete_item(item_id => $item_id);
    $dspace->delete_collection(collection_id => $col_id);
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

test_items();

#$dspace->logout();

done_testing();

