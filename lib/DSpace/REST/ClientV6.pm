package DSpace::REST::ClientV6;

use strict;

use Modern::Perl;

=head1 VERSION

Version 0.1

=head1 DESCRIPTION

B<DSpace::REST::ClientV6> - This is a REST client for DSpace 6_x.

=cut

our $VERSION = '0.1';

use JSON;
use Moose;
use MooseX::Params::Validate;
use REST::Client;
use URI::Escape;

use namespace::autoclean;

has 'host'         => (is => 'ro', isa => 'Str');
has 'client'       => (is => 'ro', lazy => 1, builder => '_build_client');
has 'dspace_token' => (is => 'rw', isa => 'Maybe[Str]');

sub _build_client {
    my ($self) = @_;
    my $client = REST::Client->new(
        host => $self->host
    );
    return $client;
}

sub _escape_param {
    my ($self, $param_name, $param_value) = @_;
    my @param_values;
    if (ref $param_value eq 'ARRAY') {
        @param_values = @$param_value;
    }
    else {
        @param_values = ($param_value);
    }
    my @escaped_params = map { uri_escape_utf8($param_name).'='.uri_escape_utf8($_) } @param_values;
    return join('&', @escaped_params);
}

sub _build_url {
    my ($self, $path, $query_params) = validated_list(
        \@_,
        path            => { isa => 'Str' },
        query_params    => { isa => 'HashRef' },
    );
    my $url = $path;
    my @non_empty_params = grep { defined $query_params->{$_} } keys %$query_params;
    # turns our query_params hash (param_name => param_value) into an array of [$param_name, $param_value] pairs)
    my @param_list = map { [$_, $query_params->{$_}] } @non_empty_params;
    my @safe_params = map { $self->_escape_param(@{$_}) } @param_list;
    if (@safe_params) {
        $url .= '?'.join('&', @safe_params);
    }
    return $url;
}

sub _build_path {
    my ($self, $path_pattern, $path_params) = validated_list(
        \@_,
        path_pattern    => { isa => 'Str' },
        path_params     => { isa => 'HashRef' }
    );
    # Should really be an anonymous sub but I could not convince the e flag to accept the &$funcname syntax
    sub escape_param_sub {
        my ($param_name, $val) = @_;
        die "No such param $param_name" unless (defined $val);
        return '/'.uri_escape_utf8($val);
    }

    (my $path = $path_pattern) =~ s!/:(\w+)!escape_param_sub($1, $path_params->{$1})!eg;
    return $path;
}

sub _handle_response {
    my ($self, $verb, $url) = @_;
    my $code = $self->client->responseCode();
    if ($code < 200 || ($code >= 300 && $code < 400) || ($code >= 600) ) {
        (my $err = $self->client->responseContent) =~ s/\n/ /g;
        die "Unexpected response code $code for $verb $url with content $err";
    }
    elsif ($code == 404) {
        die "Resource not found on the server at URL $url";
    }
    elsif ($code >= 400) {
        (my $err = $self->client->responseContent) =~ s/\n/ /g;
        die "Error while contacting the server $url: got error $code with content $err";
    }
    my $response_str = $self->client->responseContent;
    my $resp_content_type = $self->client->responseHeader('Content-Type');
    my $resp_location = $self->client->responseHeader('Location');

    my $has_response = (defined $response_str && $response_str ne '');
    if ($has_response) {
        if (defined $resp_content_type && $resp_content_type =~ m!^application/json!) {
            return decode_json($response_str);
        }
        else {
            return $response_str;
        }
    }
    elsif ($code eq 201 && defined $resp_location) {
        return $resp_location;
    }
    else {
        return undef;
    }
}

sub get_item_metadata {
    my $self = shift;
    my %params = validated_hash(\@_,
        'headers' => { isa => 'HashRef', optional => 1 },
        'item_id' => { isa => 'Str' },
        'userIP' => { isa => 'Str', optional => 1 },
        'userAgent' => { isa => 'Str', optional => 1 },
        'xforwardedfor' => { isa => 'Str', optional => 1 }
    );

    my $all_headers = {};

    if (defined $params{headers}) {
        foreach (keys %{$params{headers}}) {
            $all_headers->{$_} = $params{headers}{$_};
        }
    }
    if (defined $self->dspace_token) {
        $all_headers->{'rest-dspace-token'} = $self->dspace_token;
    }
    my $url = $self->_build_url(
        path => $self->_build_path(
            path_pattern => '/items/:item_id/metadata',
            path_params => {
                'item_id' => $params{'item_id'}
            }
        ),
        query_params => {
            'userIP' => $params{'userIP'},
            'userAgent' => $params{'userAgent'},
            'xforwardedfor' => $params{'xforwardedfor'}
        }
    );
    $self->client->GET($url, $all_headers);
    my $result = $self->_handle_response('GET', $self->host.$url);

    return $result;
}

sub add_item_metadata {
    my $self = shift;
    my %params = validated_hash(\@_,
        'headers' => { isa => 'HashRef', optional => 1 },
        'item_id' => { isa => 'Str' },
        'userIP' => { isa => 'Str', optional => 1 },
        'userAgent' => { isa => 'Str', optional => 1 },
        'xforwardedfor' => { isa => 'Str', optional => 1 },
        'entity' => { isa => 'Item' }
    );

    my $all_headers = {};

    if (defined $params{headers}) {
        foreach (keys %{$params{headers}}) {
            $all_headers->{$_} = $params{headers}{$_};
        }
    }
    if (defined $self->dspace_token) {
        $all_headers->{'rest-dspace-token'} = $self->dspace_token;
    }
    my $url = $self->_build_url(
        path => $self->_build_path(
            path_pattern => '/items/:item_id/metadata',
            path_params => {
                'item_id' => $params{'item_id'}
            }
        ),
        query_params => {
            'userIP' => $params{'userIP'},
            'userAgent' => $params{'userAgent'},
            'xforwardedfor' => $params{'xforwardedfor'}
        }
    );
    my $transformed_entity = $params{entity};
    if (defined $transformed_entity) {
        my $request_content_type = $all_headers->{'Content-Type'};
        $request_content_type = '' if (!defined $request_content_type);
        if ($request_content_type =~ m,^application/json,) {
            $transformed_entity = encode_json($transformed_entity);
        }
    }
    $self->client->POST($url, $transformed_entity, $all_headers);
    my $result = $self->_handle_response('POST', $self->host.$url);

    return $result;
}

sub update_item_metadata {
    my $self = shift;
    my %params = validated_hash(\@_,
        'headers' => { isa => 'HashRef', optional => 1 },
        'item_id' => { isa => 'Str' },
        'userIP' => { isa => 'Str', optional => 1 },
        'userAgent' => { isa => 'Str', optional => 1 },
        'xforwardedfor' => { isa => 'Str', optional => 1 }
    );

    my $all_headers = {};

    if (defined $params{headers}) {
        foreach (keys %{$params{headers}}) {
            $all_headers->{$_} = $params{headers}{$_};
        }
    }
    if (defined $self->dspace_token) {
        $all_headers->{'rest-dspace-token'} = $self->dspace_token;
    }
    my $url = $self->_build_url(
        path => $self->_build_path(
            path_pattern => '/items/:item_id/metadata',
            path_params => {
                'item_id' => $params{'item_id'}
            }
        ),
        query_params => {
            'userIP' => $params{'userIP'},
            'userAgent' => $params{'userAgent'},
            'xforwardedfor' => $params{'xforwardedfor'}
        }
    );
    $self->client->PUT($url, undef, $all_headers);
    my $result = $self->_handle_response('PUT', $self->host.$url);

    return $result;
}

sub delete_item_metadata {
    my $self = shift;
    my %params = validated_hash(\@_,
        'headers' => { isa => 'HashRef', optional => 1 },
        'item_id' => { isa => 'Str' },
        'userIP' => { isa => 'Str', optional => 1 },
        'userAgent' => { isa => 'Str', optional => 1 },
        'xforwardedfor' => { isa => 'Str', optional => 1 }
    );

    my $all_headers = {};

    if (defined $params{headers}) {
        foreach (keys %{$params{headers}}) {
            $all_headers->{$_} = $params{headers}{$_};
        }
    }
    if (defined $self->dspace_token) {
        $all_headers->{'rest-dspace-token'} = $self->dspace_token;
    }
    my $url = $self->_build_url(
        path => $self->_build_path(
            path_pattern => '/items/:item_id/metadata',
            path_params => {
                'item_id' => $params{'item_id'}
            }
        ),
        query_params => {
            'userIP' => $params{'userIP'},
            'userAgent' => $params{'userAgent'},
            'xforwardedfor' => $params{'xforwardedfor'}
        }
    );
    $self->client->DELETE($url, $all_headers);
    my $result = $self->_handle_response('DELETE', $self->host.$url);

    return $result;
}

sub add_item_bitstream {
    my $self = shift;
    my %params = validated_hash(\@_,
        'headers' => { isa => 'HashRef', optional => 1 },
        'item_id' => { isa => 'Str' },
        'name' => { isa => 'Str', optional => 1 },
        'description' => { isa => 'Str', optional => 1 },
        'groupId' => { isa => 'Str', optional => 1 },
        'year' => { isa => 'Int', optional => 1 },
        'month' => { isa => 'Int', optional => 1 },
        'day' => { isa => 'Int', optional => 1 },
        'userIP' => { isa => 'Str', optional => 1 },
        'userAgent' => { isa => 'Str', optional => 1 },
        'xforwardedfor' => { isa => 'Str', optional => 1 },
        'entity' => { isa => 'Item' }
    );

    my $all_headers = {};

    if (defined $params{headers}) {
        foreach (keys %{$params{headers}}) {
            $all_headers->{$_} = $params{headers}{$_};
        }
    }
    if (defined $self->dspace_token) {
        $all_headers->{'rest-dspace-token'} = $self->dspace_token;
    }
    my $url = $self->_build_url(
        path => $self->_build_path(
            path_pattern => '/items/:item_id/bitstreams',
            path_params => {
                'item_id' => $params{'item_id'}
            }
        ),
        query_params => {
            'name' => $params{'name'},
            'description' => $params{'description'},
            'groupId' => $params{'groupId'},
            'year' => $params{'year'},
            'month' => $params{'month'},
            'day' => $params{'day'},
            'userIP' => $params{'userIP'},
            'userAgent' => $params{'userAgent'},
            'xforwardedfor' => $params{'xforwardedfor'}
        }
    );
    my $transformed_entity = $params{entity};
    if (defined $transformed_entity) {
        my $request_content_type = $all_headers->{'Content-Type'};
        $request_content_type = '' if (!defined $request_content_type);
        if ($request_content_type =~ m,^application/json,) {
            $transformed_entity = encode_json($transformed_entity);
        }
    }
    $self->client->POST($url, $transformed_entity, $all_headers);
    my $result = $self->_handle_response('POST', $self->host.$url);

    return $result;
}

sub get_item_bitstreams {
    my $self = shift;
    my %params = validated_hash(\@_,
        'headers' => { isa => 'HashRef', optional => 1 },
        'item_id' => { isa => 'Str' },
        'limit' => { isa => 'Int', optional => 1 },
        'offset' => { isa => 'Int', optional => 1 },
        'userIP' => { isa => 'Str', optional => 1 },
        'userAgent' => { isa => 'Str', optional => 1 },
        'xforwardedfor' => { isa => 'Str', optional => 1 }
    );

    my $all_headers = {};

    if (defined $params{headers}) {
        foreach (keys %{$params{headers}}) {
            $all_headers->{$_} = $params{headers}{$_};
        }
    }
    if (defined $self->dspace_token) {
        $all_headers->{'rest-dspace-token'} = $self->dspace_token;
    }
    my $url = $self->_build_url(
        path => $self->_build_path(
            path_pattern => '/items/:item_id/bitstreams',
            path_params => {
                'item_id' => $params{'item_id'}
            }
        ),
        query_params => {
            'limit' => $params{'limit'},
            'offset' => $params{'offset'},
            'userIP' => $params{'userIP'},
            'userAgent' => $params{'userAgent'},
            'xforwardedfor' => $params{'xforwardedfor'}
        }
    );
    $self->client->GET($url, $all_headers);
    my $result = $self->_handle_response('GET', $self->host.$url);

    return $result;
}

sub delete_item_bitstream {
    my $self = shift;
    my %params = validated_hash(\@_,
        'headers' => { isa => 'HashRef', optional => 1 },
        'item_id' => { isa => 'Str' },
        'bitstream_id' => { isa => 'Str' },
        'userIP' => { isa => 'Str', optional => 1 },
        'userAgent' => { isa => 'Str', optional => 1 },
        'xforwardedfor' => { isa => 'Str', optional => 1 }
    );

    my $all_headers = {};

    if (defined $params{headers}) {
        foreach (keys %{$params{headers}}) {
            $all_headers->{$_} = $params{headers}{$_};
        }
    }
    if (defined $self->dspace_token) {
        $all_headers->{'rest-dspace-token'} = $self->dspace_token;
    }
    my $url = $self->_build_url(
        path => $self->_build_path(
            path_pattern => '/items/:item_id/bitstreams/:bitstream_id',
            path_params => {
                'item_id' => $params{'item_id'},
                'bitstream_id' => $params{'bitstream_id'}
            }
        ),
        query_params => {
            'userIP' => $params{'userIP'},
            'userAgent' => $params{'userAgent'},
            'xforwardedfor' => $params{'xforwardedfor'}
        }
    );
    $self->client->DELETE($url, $all_headers);
    my $result = $self->_handle_response('DELETE', $self->host.$url);

    return $result;
}

sub find_items_by_metadata_field {
    my $self = shift;
    my %params = validated_hash(\@_,
        'headers' => { isa => 'HashRef', optional => 1 },
        'expand' => { isa => 'Str', optional => 1 },
        'userIP' => { isa => 'Str', optional => 1 },
        'userAgent' => { isa => 'Str', optional => 1 },
        'xforwardedfor' => { isa => 'Str', optional => 1 },
        'entity' => { isa => 'Item' }
    );

    my $all_headers = {};

    if (defined $params{headers}) {
        foreach (keys %{$params{headers}}) {
            $all_headers->{$_} = $params{headers}{$_};
        }
    }
    if (defined $self->dspace_token) {
        $all_headers->{'rest-dspace-token'} = $self->dspace_token;
    }
    my $url = $self->_build_url(
        path => $self->_build_path(
            path_pattern => '/items/find-by-metadata-field',
            path_params => {
                
            }
        ),
        query_params => {
            'expand' => $params{'expand'},
            'userIP' => $params{'userIP'},
            'userAgent' => $params{'userAgent'},
            'xforwardedfor' => $params{'xforwardedfor'}
        }
    );
    my $transformed_entity = $params{entity};
    if (defined $transformed_entity) {
        my $request_content_type = $all_headers->{'Content-Type'};
        $request_content_type = '' if (!defined $request_content_type);
        if ($request_content_type =~ m,^application/json,) {
            $transformed_entity = encode_json($transformed_entity);
        }
    }
    $self->client->POST($url, $transformed_entity, $all_headers);
    my $result = $self->_handle_response('POST', $self->host.$url);

    return $result;
}

sub delete_item {
    my $self = shift;
    my %params = validated_hash(\@_,
        'headers' => { isa => 'HashRef', optional => 1 },
        'item_id' => { isa => 'Str' },
        'userIP' => { isa => 'Str', optional => 1 },
        'userAgent' => { isa => 'Str', optional => 1 },
        'xforwardedfor' => { isa => 'Str', optional => 1 }
    );

    my $all_headers = {};

    if (defined $params{headers}) {
        foreach (keys %{$params{headers}}) {
            $all_headers->{$_} = $params{headers}{$_};
        }
    }
    if (defined $self->dspace_token) {
        $all_headers->{'rest-dspace-token'} = $self->dspace_token;
    }
    my $url = $self->_build_url(
        path => $self->_build_path(
            path_pattern => '/items/:item_id',
            path_params => {
                'item_id' => $params{'item_id'}
            }
        ),
        query_params => {
            'userIP' => $params{'userIP'},
            'userAgent' => $params{'userAgent'},
            'xforwardedfor' => $params{'xforwardedfor'}
        }
    );
    $self->client->DELETE($url, $all_headers);
    my $result = $self->_handle_response('DELETE', $self->host.$url);

    return $result;
}

sub get_item {
    my $self = shift;
    my %params = validated_hash(\@_,
        'headers' => { isa => 'HashRef', optional => 1 },
        'item_id' => { isa => 'Str' },
        'expand' => { isa => 'Str', optional => 1 },
        'userIP' => { isa => 'Str', optional => 1 },
        'userAgent' => { isa => 'Str', optional => 1 },
        'xforwardedfor' => { isa => 'Str', optional => 1 }
    );

    my $all_headers = {};

    if (defined $params{headers}) {
        foreach (keys %{$params{headers}}) {
            $all_headers->{$_} = $params{headers}{$_};
        }
    }
    if (defined $self->dspace_token) {
        $all_headers->{'rest-dspace-token'} = $self->dspace_token;
    }
    my $url = $self->_build_url(
        path => $self->_build_path(
            path_pattern => '/items/:item_id',
            path_params => {
                'item_id' => $params{'item_id'}
            }
        ),
        query_params => {
            'expand' => $params{'expand'},
            'userIP' => $params{'userIP'},
            'userAgent' => $params{'userAgent'},
            'xforwardedfor' => $params{'xforwardedfor'}
        }
    );
    $self->client->GET($url, $all_headers);
    my $result = $self->_handle_response('GET', $self->host.$url);

    return $result;
}

sub get_items {
    my $self = shift;
    my %params = validated_hash(\@_,
        'headers' => { isa => 'HashRef', optional => 1 },
        'expand' => { isa => 'Str', optional => 1 },
        'limit' => { isa => 'Int', optional => 1 },
        'offset' => { isa => 'Int', optional => 1 },
        'userIP' => { isa => 'Str', optional => 1 },
        'userAgent' => { isa => 'Str', optional => 1 },
        'xforwardedfor' => { isa => 'Str', optional => 1 }
    );

    my $all_headers = {};

    if (defined $params{headers}) {
        foreach (keys %{$params{headers}}) {
            $all_headers->{$_} = $params{headers}{$_};
        }
    }
    if (defined $self->dspace_token) {
        $all_headers->{'rest-dspace-token'} = $self->dspace_token;
    }
    my $url = $self->_build_url(
        path => $self->_build_path(
            path_pattern => '/items',
            path_params => {
                
            }
        ),
        query_params => {
            'expand' => $params{'expand'},
            'limit' => $params{'limit'},
            'offset' => $params{'offset'},
            'userIP' => $params{'userIP'},
            'userAgent' => $params{'userAgent'},
            'xforwardedfor' => $params{'xforwardedfor'}
        }
    );
    $self->client->GET($url, $all_headers);
    my $result = $self->_handle_response('GET', $self->host.$url);

    return $result;
}

sub login {
    my $self = shift;
    my %params = validated_hash(\@_,
        'headers' => { isa => 'HashRef', optional => 1 },
        'entity' => { isa => 'Item' }
    );

    my $all_headers = {};

    if (defined $params{headers}) {
        foreach (keys %{$params{headers}}) {
            $all_headers->{$_} = $params{headers}{$_};
        }
    }
    if (defined $self->dspace_token) {
        $all_headers->{'rest-dspace-token'} = $self->dspace_token;
    }
    my $url = $self->_build_url(
        path => $self->_build_path(
            path_pattern => '/login',
            path_params => {
                
            }
        ),
        query_params => {
            
        }
    );
    my $transformed_entity = $params{entity};
    if (defined $transformed_entity) {
        my $request_content_type = $all_headers->{'Content-Type'};
        $request_content_type = '' if (!defined $request_content_type);
        if ($request_content_type =~ m,^application/json,) {
            $transformed_entity = encode_json($transformed_entity);
        }
    }
    $self->client->POST($url, $transformed_entity, $all_headers);
    my $result = $self->_handle_response('POST', $self->host.$url);
        $self->dspace_token($result);

    return $result;
}

sub logout {
    my $self = shift;
    my %params = validated_hash(\@_,
        'headers' => { isa => 'HashRef', optional => 1 },
        
    );

    my $all_headers = {};
    $all_headers->{'Content-Type'} = 'application/json';

    if (defined $params{headers}) {
        foreach (keys %{$params{headers}}) {
            $all_headers->{$_} = $params{headers}{$_};
        }
    }
    if (defined $self->dspace_token) {
        $all_headers->{'rest-dspace-token'} = $self->dspace_token;
    }
    my $url = $self->_build_url(
        path => $self->_build_path(
            path_pattern => '/logout',
            path_params => {
                
            }
        ),
        query_params => {
            
        }
    );
    $self->client->POST($url, undef, $all_headers);
    my $result = $self->_handle_response('POST', $self->host.$url);

    return $result;
}

sub status {
    my $self = shift;
    my %params = validated_hash(\@_,
        'headers' => { isa => 'HashRef', optional => 1 },
        
    );

    my $all_headers = {};

    if (defined $params{headers}) {
        foreach (keys %{$params{headers}}) {
            $all_headers->{$_} = $params{headers}{$_};
        }
    }
    if (defined $self->dspace_token) {
        $all_headers->{'rest-dspace-token'} = $self->dspace_token;
    }
    my $url = $self->_build_url(
        path => $self->_build_path(
            path_pattern => '/status',
            path_params => {
                
            }
        ),
        query_params => {
            
        }
    );
    $self->client->GET($url, $all_headers);
    my $result = $self->_handle_response('GET', $self->host.$url);

    return $result;
}

sub test {
    my $self = shift;
    my %params = validated_hash(\@_,
        'headers' => { isa => 'HashRef', optional => 1 },
        
    );

    my $all_headers = {};

    if (defined $params{headers}) {
        foreach (keys %{$params{headers}}) {
            $all_headers->{$_} = $params{headers}{$_};
        }
    }
    if (defined $self->dspace_token) {
        $all_headers->{'rest-dspace-token'} = $self->dspace_token;
    }
    my $url = $self->_build_url(
        path => $self->_build_path(
            path_pattern => '/test',
            path_params => {
                
            }
        ),
        query_params => {
            
        }
    );
    $self->client->GET($url, $all_headers);
    my $result = $self->_handle_response('GET', $self->host.$url);

    return $result;
}

sub say_html_hello {
    my $self = shift;
    my %params = validated_hash(\@_,
        'headers' => { isa => 'HashRef', optional => 1 },
        
    );

    my $all_headers = {};

    if (defined $params{headers}) {
        foreach (keys %{$params{headers}}) {
            $all_headers->{$_} = $params{headers}{$_};
        }
    }
    if (defined $self->dspace_token) {
        $all_headers->{'rest-dspace-token'} = $self->dspace_token;
    }
    my $url = $self->_build_url(
        path => $self->_build_path(
            path_pattern => '/',
            path_params => {
                
            }
        ),
        query_params => {
            
        }
    );
    $self->client->GET($url, $all_headers);
    my $result = $self->_handle_response('GET', $self->host.$url);

    return $result;
}

sub get_object {
    my $self = shift;
    my %params = validated_hash(\@_,
        'headers' => { isa => 'HashRef', optional => 1 },
        'prefix' => { isa => 'Str' },
        'suffix' => { isa => 'Str' },
        'expand' => { isa => 'Str', optional => 1 }
    );

    my $all_headers = {};

    if (defined $params{headers}) {
        foreach (keys %{$params{headers}}) {
            $all_headers->{$_} = $params{headers}{$_};
        }
    }
    if (defined $self->dspace_token) {
        $all_headers->{'rest-dspace-token'} = $self->dspace_token;
    }
    my $url = $self->_build_url(
        path => $self->_build_path(
            path_pattern => '/handle/:prefix/:suffix',
            path_params => {
                'prefix' => $params{'prefix'},
                'suffix' => $params{'suffix'}
            }
        ),
        query_params => {
            'expand' => $params{'expand'}
        }
    );
    $self->client->GET($url, $all_headers);
    my $result = $self->_handle_response('GET', $self->host.$url);

    return $result;
}

sub get_bitstream_data {
    my $self = shift;
    my %params = validated_hash(\@_,
        'headers' => { isa => 'HashRef', optional => 1 },
        'bitstream_id' => { isa => 'Str' },
        'userIP' => { isa => 'Str', optional => 1 },
        'userAgent' => { isa => 'Str', optional => 1 },
        'xforwardedfor' => { isa => 'Str', optional => 1 }
    );

    my $all_headers = {};

    if (defined $params{headers}) {
        foreach (keys %{$params{headers}}) {
            $all_headers->{$_} = $params{headers}{$_};
        }
    }
    if (defined $self->dspace_token) {
        $all_headers->{'rest-dspace-token'} = $self->dspace_token;
    }
    my $url = $self->_build_url(
        path => $self->_build_path(
            path_pattern => '/bitstreams/:bitstream_id/retrieve',
            path_params => {
                'bitstream_id' => $params{'bitstream_id'}
            }
        ),
        query_params => {
            'userIP' => $params{'userIP'},
            'userAgent' => $params{'userAgent'},
            'xforwardedfor' => $params{'xforwardedfor'}
        }
    );
    $self->client->GET($url, $all_headers);
    my $result = $self->_handle_response('GET', $self->host.$url);

    return $result;
}

sub add_bitstream_policy {
    my $self = shift;
    my %params = validated_hash(\@_,
        'headers' => { isa => 'HashRef', optional => 1 },
        'bitstream_id' => { isa => 'Str' },
        'userIP' => { isa => 'Str', optional => 1 },
        'userAgent' => { isa => 'Str', optional => 1 },
        'xforwardedfor' => { isa => 'Str', optional => 1 },
        'entity' => { isa => 'Item' }
    );

    my $all_headers = {};

    if (defined $params{headers}) {
        foreach (keys %{$params{headers}}) {
            $all_headers->{$_} = $params{headers}{$_};
        }
    }
    if (defined $self->dspace_token) {
        $all_headers->{'rest-dspace-token'} = $self->dspace_token;
    }
    my $url = $self->_build_url(
        path => $self->_build_path(
            path_pattern => '/bitstreams/:bitstream_id/policy',
            path_params => {
                'bitstream_id' => $params{'bitstream_id'}
            }
        ),
        query_params => {
            'userIP' => $params{'userIP'},
            'userAgent' => $params{'userAgent'},
            'xforwardedfor' => $params{'xforwardedfor'}
        }
    );
    my $transformed_entity = $params{entity};
    if (defined $transformed_entity) {
        my $request_content_type = $all_headers->{'Content-Type'};
        $request_content_type = '' if (!defined $request_content_type);
        if ($request_content_type =~ m,^application/json,) {
            $transformed_entity = encode_json($transformed_entity);
        }
    }
    $self->client->POST($url, $transformed_entity, $all_headers);
    my $result = $self->_handle_response('POST', $self->host.$url);

    return $result;
}

sub get_bitstream_policies {
    my $self = shift;
    my %params = validated_hash(\@_,
        'headers' => { isa => 'HashRef', optional => 1 },
        'bitstream_id' => { isa => 'Str' }
    );

    my $all_headers = {};

    if (defined $params{headers}) {
        foreach (keys %{$params{headers}}) {
            $all_headers->{$_} = $params{headers}{$_};
        }
    }
    if (defined $self->dspace_token) {
        $all_headers->{'rest-dspace-token'} = $self->dspace_token;
    }
    my $url = $self->_build_url(
        path => $self->_build_path(
            path_pattern => '/bitstreams/:bitstream_id/policy',
            path_params => {
                'bitstream_id' => $params{'bitstream_id'}
            }
        ),
        query_params => {
            
        }
    );
    $self->client->GET($url, $all_headers);
    my $result = $self->_handle_response('GET', $self->host.$url);

    return $result;
}

sub update_bitstream {
    my $self = shift;
    my %params = validated_hash(\@_,
        'headers' => { isa => 'HashRef', optional => 1 },
        'bitstream_id' => { isa => 'Str' },
        'userIP' => { isa => 'Str', optional => 1 },
        'userAgent' => { isa => 'Str', optional => 1 },
        'xforwardedfor' => { isa => 'Str', optional => 1 },
        'entity' => { isa => 'Item' }
    );

    my $all_headers = {};

    if (defined $params{headers}) {
        foreach (keys %{$params{headers}}) {
            $all_headers->{$_} = $params{headers}{$_};
        }
    }
    if (defined $self->dspace_token) {
        $all_headers->{'rest-dspace-token'} = $self->dspace_token;
    }
    my $url = $self->_build_url(
        path => $self->_build_path(
            path_pattern => '/bitstreams/:bitstream_id',
            path_params => {
                'bitstream_id' => $params{'bitstream_id'}
            }
        ),
        query_params => {
            'userIP' => $params{'userIP'},
            'userAgent' => $params{'userAgent'},
            'xforwardedfor' => $params{'xforwardedfor'}
        }
    );
    my $transformed_entity = $params{entity};
    if (defined $transformed_entity) {
        my $request_content_type = $all_headers->{'Content-Type'};
        $request_content_type = '' if (!defined $request_content_type);
        if ($request_content_type =~ m,^application/json,) {
            $transformed_entity = encode_json($transformed_entity);
        }
    }
    $self->client->PUT($url, $transformed_entity, $all_headers);
    my $result = $self->_handle_response('PUT', $self->host.$url);

    return $result;
}

sub delete_bitstream {
    my $self = shift;
    my %params = validated_hash(\@_,
        'headers' => { isa => 'HashRef', optional => 1 },
        'bitstream_id' => { isa => 'Str' },
        'userIP' => { isa => 'Str', optional => 1 },
        'userAgent' => { isa => 'Str', optional => 1 },
        'xforwardedfor' => { isa => 'Str', optional => 1 }
    );

    my $all_headers = {};

    if (defined $params{headers}) {
        foreach (keys %{$params{headers}}) {
            $all_headers->{$_} = $params{headers}{$_};
        }
    }
    if (defined $self->dspace_token) {
        $all_headers->{'rest-dspace-token'} = $self->dspace_token;
    }
    my $url = $self->_build_url(
        path => $self->_build_path(
            path_pattern => '/bitstreams/:bitstream_id',
            path_params => {
                'bitstream_id' => $params{'bitstream_id'}
            }
        ),
        query_params => {
            'userIP' => $params{'userIP'},
            'userAgent' => $params{'userAgent'},
            'xforwardedfor' => $params{'xforwardedfor'}
        }
    );
    $self->client->DELETE($url, $all_headers);
    my $result = $self->_handle_response('DELETE', $self->host.$url);

    return $result;
}

sub get_bitstream {
    my $self = shift;
    my %params = validated_hash(\@_,
        'headers' => { isa => 'HashRef', optional => 1 },
        'bitstream_id' => { isa => 'Str' },
        'expand' => { isa => 'Str', optional => 1 },
        'userIP' => { isa => 'Str', optional => 1 },
        'userAgent' => { isa => 'Str', optional => 1 },
        'xforwardedfor' => { isa => 'Str', optional => 1 }
    );

    my $all_headers = {};

    if (defined $params{headers}) {
        foreach (keys %{$params{headers}}) {
            $all_headers->{$_} = $params{headers}{$_};
        }
    }
    if (defined $self->dspace_token) {
        $all_headers->{'rest-dspace-token'} = $self->dspace_token;
    }
    my $url = $self->_build_url(
        path => $self->_build_path(
            path_pattern => '/bitstreams/:bitstream_id',
            path_params => {
                'bitstream_id' => $params{'bitstream_id'}
            }
        ),
        query_params => {
            'expand' => $params{'expand'},
            'userIP' => $params{'userIP'},
            'userAgent' => $params{'userAgent'},
            'xforwardedfor' => $params{'xforwardedfor'}
        }
    );
    $self->client->GET($url, $all_headers);
    my $result = $self->_handle_response('GET', $self->host.$url);

    return $result;
}

sub update_bitstream_data {
    my $self = shift;
    my %params = validated_hash(\@_,
        'headers' => { isa => 'HashRef', optional => 1 },
        'bitstream_id' => { isa => 'Str' },
        'userIP' => { isa => 'Str', optional => 1 },
        'userAgent' => { isa => 'Str', optional => 1 },
        'xforwardedfor' => { isa => 'Str', optional => 1 },
        'entity' => { isa => 'Item' }
    );

    my $all_headers = {};

    if (defined $params{headers}) {
        foreach (keys %{$params{headers}}) {
            $all_headers->{$_} = $params{headers}{$_};
        }
    }
    if (defined $self->dspace_token) {
        $all_headers->{'rest-dspace-token'} = $self->dspace_token;
    }
    my $url = $self->_build_url(
        path => $self->_build_path(
            path_pattern => '/bitstreams/:bitstream_id/data',
            path_params => {
                'bitstream_id' => $params{'bitstream_id'}
            }
        ),
        query_params => {
            'userIP' => $params{'userIP'},
            'userAgent' => $params{'userAgent'},
            'xforwardedfor' => $params{'xforwardedfor'}
        }
    );
    my $transformed_entity = $params{entity};
    if (defined $transformed_entity) {
        my $request_content_type = $all_headers->{'Content-Type'};
        $request_content_type = '' if (!defined $request_content_type);
        if ($request_content_type =~ m,^application/json,) {
            $transformed_entity = encode_json($transformed_entity);
        }
    }
    $self->client->PUT($url, $transformed_entity, $all_headers);
    my $result = $self->_handle_response('PUT', $self->host.$url);

    return $result;
}

sub delete_bitstream_policy {
    my $self = shift;
    my %params = validated_hash(\@_,
        'headers' => { isa => 'HashRef', optional => 1 },
        'policy_id' => { isa => 'Int' },
        'bitstream_id' => { isa => 'Str' },
        'userIP' => { isa => 'Str', optional => 1 },
        'userAgent' => { isa => 'Str', optional => 1 },
        'xforwardedfor' => { isa => 'Str', optional => 1 }
    );

    my $all_headers = {};

    if (defined $params{headers}) {
        foreach (keys %{$params{headers}}) {
            $all_headers->{$_} = $params{headers}{$_};
        }
    }
    if (defined $self->dspace_token) {
        $all_headers->{'rest-dspace-token'} = $self->dspace_token;
    }
    my $url = $self->_build_url(
        path => $self->_build_path(
            path_pattern => '/bitstreams/:bitstream_id/policy/:policy_id',
            path_params => {
                'policy_id' => $params{'policy_id'},
                'bitstream_id' => $params{'bitstream_id'}
            }
        ),
        query_params => {
            'userIP' => $params{'userIP'},
            'userAgent' => $params{'userAgent'},
            'xforwardedfor' => $params{'xforwardedfor'}
        }
    );
    $self->client->DELETE($url, $all_headers);
    my $result = $self->_handle_response('DELETE', $self->host.$url);

    return $result;
}

sub get_bitstreams {
    my $self = shift;
    my %params = validated_hash(\@_,
        'headers' => { isa => 'HashRef', optional => 1 },
        'expand' => { isa => 'Str', optional => 1 },
        'limit' => { isa => 'Int', optional => 1 },
        'offset' => { isa => 'Int', optional => 1 },
        'userIP' => { isa => 'Str', optional => 1 },
        'userAgent' => { isa => 'Str', optional => 1 },
        'xforwardedfor' => { isa => 'Str', optional => 1 }
    );

    my $all_headers = {};

    if (defined $params{headers}) {
        foreach (keys %{$params{headers}}) {
            $all_headers->{$_} = $params{headers}{$_};
        }
    }
    if (defined $self->dspace_token) {
        $all_headers->{'rest-dspace-token'} = $self->dspace_token;
    }
    my $url = $self->_build_url(
        path => $self->_build_path(
            path_pattern => '/bitstreams',
            path_params => {
                
            }
        ),
        query_params => {
            'expand' => $params{'expand'},
            'limit' => $params{'limit'},
            'offset' => $params{'offset'},
            'userIP' => $params{'userIP'},
            'userAgent' => $params{'userAgent'},
            'xforwardedfor' => $params{'xforwardedfor'}
        }
    );
    $self->client->GET($url, $all_headers);
    my $result = $self->_handle_response('GET', $self->host.$url);

    return $result;
}

sub get_top_communities {
    my $self = shift;
    my %params = validated_hash(\@_,
        'headers' => { isa => 'HashRef', optional => 1 },
        'expand' => { isa => 'Str', optional => 1 },
        'limit' => { isa => 'Int', optional => 1 },
        'offset' => { isa => 'Int', optional => 1 },
        'userIP' => { isa => 'Str', optional => 1 },
        'userAgent' => { isa => 'Str', optional => 1 },
        'xforwardedfor' => { isa => 'Str', optional => 1 }
    );

    my $all_headers = {};

    if (defined $params{headers}) {
        foreach (keys %{$params{headers}}) {
            $all_headers->{$_} = $params{headers}{$_};
        }
    }
    if (defined $self->dspace_token) {
        $all_headers->{'rest-dspace-token'} = $self->dspace_token;
    }
    my $url = $self->_build_url(
        path => $self->_build_path(
            path_pattern => '/communities/top-communities',
            path_params => {
                
            }
        ),
        query_params => {
            'expand' => $params{'expand'},
            'limit' => $params{'limit'},
            'offset' => $params{'offset'},
            'userIP' => $params{'userIP'},
            'userAgent' => $params{'userAgent'},
            'xforwardedfor' => $params{'xforwardedfor'}
        }
    );
    $self->client->GET($url, $all_headers);
    my $result = $self->_handle_response('GET', $self->host.$url);

    return $result;
}

sub get_community_collections {
    my $self = shift;
    my %params = validated_hash(\@_,
        'headers' => { isa => 'HashRef', optional => 1 },
        'community_id' => { isa => 'Str' },
        'expand' => { isa => 'Str', optional => 1 },
        'limit' => { isa => 'Int', optional => 1 },
        'offset' => { isa => 'Int', optional => 1 },
        'userIP' => { isa => 'Str', optional => 1 },
        'userAgent' => { isa => 'Str', optional => 1 },
        'xforwardedfor' => { isa => 'Str', optional => 1 }
    );

    my $all_headers = {};

    if (defined $params{headers}) {
        foreach (keys %{$params{headers}}) {
            $all_headers->{$_} = $params{headers}{$_};
        }
    }
    if (defined $self->dspace_token) {
        $all_headers->{'rest-dspace-token'} = $self->dspace_token;
    }
    my $url = $self->_build_url(
        path => $self->_build_path(
            path_pattern => '/communities/:community_id/collections',
            path_params => {
                'community_id' => $params{'community_id'}
            }
        ),
        query_params => {
            'expand' => $params{'expand'},
            'limit' => $params{'limit'},
            'offset' => $params{'offset'},
            'userIP' => $params{'userIP'},
            'userAgent' => $params{'userAgent'},
            'xforwardedfor' => $params{'xforwardedfor'}
        }
    );
    $self->client->GET($url, $all_headers);
    my $result = $self->_handle_response('GET', $self->host.$url);

    return $result;
}

sub add_community_collection {
    my $self = shift;
    my %params = validated_hash(\@_,
        'headers' => { isa => 'HashRef', optional => 1 },
        'community_id' => { isa => 'Str' },
        'userIP' => { isa => 'Str', optional => 1 },
        'userAgent' => { isa => 'Str', optional => 1 },
        'xforwardedfor' => { isa => 'Str', optional => 1 },
        'entity' => { isa => 'Item' }
    );

    my $all_headers = {};

    if (defined $params{headers}) {
        foreach (keys %{$params{headers}}) {
            $all_headers->{$_} = $params{headers}{$_};
        }
    }
    if (defined $self->dspace_token) {
        $all_headers->{'rest-dspace-token'} = $self->dspace_token;
    }
    my $url = $self->_build_url(
        path => $self->_build_path(
            path_pattern => '/communities/:community_id/collections',
            path_params => {
                'community_id' => $params{'community_id'}
            }
        ),
        query_params => {
            'userIP' => $params{'userIP'},
            'userAgent' => $params{'userAgent'},
            'xforwardedfor' => $params{'xforwardedfor'}
        }
    );
    my $transformed_entity = $params{entity};
    if (defined $transformed_entity) {
        my $request_content_type = $all_headers->{'Content-Type'};
        $request_content_type = '' if (!defined $request_content_type);
        if ($request_content_type =~ m,^application/json,) {
            $transformed_entity = encode_json($transformed_entity);
        }
    }
    $self->client->POST($url, $transformed_entity, $all_headers);
    my $result = $self->_handle_response('POST', $self->host.$url);

    return $result;
}

sub get_community_communities {
    my $self = shift;
    my %params = validated_hash(\@_,
        'headers' => { isa => 'HashRef', optional => 1 },
        'community_id' => { isa => 'Str' },
        'expand' => { isa => 'Str', optional => 1 },
        'limit' => { isa => 'Int', optional => 1 },
        'offset' => { isa => 'Int', optional => 1 },
        'userIP' => { isa => 'Str', optional => 1 },
        'userAgent' => { isa => 'Str', optional => 1 },
        'xforwardedfor' => { isa => 'Str', optional => 1 }
    );

    my $all_headers = {};

    if (defined $params{headers}) {
        foreach (keys %{$params{headers}}) {
            $all_headers->{$_} = $params{headers}{$_};
        }
    }
    if (defined $self->dspace_token) {
        $all_headers->{'rest-dspace-token'} = $self->dspace_token;
    }
    my $url = $self->_build_url(
        path => $self->_build_path(
            path_pattern => '/communities/:community_id/communities',
            path_params => {
                'community_id' => $params{'community_id'}
            }
        ),
        query_params => {
            'expand' => $params{'expand'},
            'limit' => $params{'limit'},
            'offset' => $params{'offset'},
            'userIP' => $params{'userIP'},
            'userAgent' => $params{'userAgent'},
            'xforwardedfor' => $params{'xforwardedfor'}
        }
    );
    $self->client->GET($url, $all_headers);
    my $result = $self->_handle_response('GET', $self->host.$url);

    return $result;
}

sub add_community_community {
    my $self = shift;
    my %params = validated_hash(\@_,
        'headers' => { isa => 'HashRef', optional => 1 },
        'community_id' => { isa => 'Str' },
        'userIP' => { isa => 'Str', optional => 1 },
        'userAgent' => { isa => 'Str', optional => 1 },
        'xforwardedfor' => { isa => 'Str', optional => 1 },
        'entity' => { isa => 'Item' }
    );

    my $all_headers = {};

    if (defined $params{headers}) {
        foreach (keys %{$params{headers}}) {
            $all_headers->{$_} = $params{headers}{$_};
        }
    }
    if (defined $self->dspace_token) {
        $all_headers->{'rest-dspace-token'} = $self->dspace_token;
    }
    my $url = $self->_build_url(
        path => $self->_build_path(
            path_pattern => '/communities/:community_id/communities',
            path_params => {
                'community_id' => $params{'community_id'}
            }
        ),
        query_params => {
            'userIP' => $params{'userIP'},
            'userAgent' => $params{'userAgent'},
            'xforwardedfor' => $params{'xforwardedfor'}
        }
    );
    my $transformed_entity = $params{entity};
    if (defined $transformed_entity) {
        my $request_content_type = $all_headers->{'Content-Type'};
        $request_content_type = '' if (!defined $request_content_type);
        if ($request_content_type =~ m,^application/json,) {
            $transformed_entity = encode_json($transformed_entity);
        }
    }
    $self->client->POST($url, $transformed_entity, $all_headers);
    my $result = $self->_handle_response('POST', $self->host.$url);

    return $result;
}

sub update_community {
    my $self = shift;
    my %params = validated_hash(\@_,
        'headers' => { isa => 'HashRef', optional => 1 },
        'community_id' => { isa => 'Str' },
        'userIP' => { isa => 'Str', optional => 1 },
        'userAgent' => { isa => 'Str', optional => 1 },
        'xforwardedfor' => { isa => 'Str', optional => 1 },
        'entity' => { isa => 'Item' }
    );

    my $all_headers = {};

    if (defined $params{headers}) {
        foreach (keys %{$params{headers}}) {
            $all_headers->{$_} = $params{headers}{$_};
        }
    }
    if (defined $self->dspace_token) {
        $all_headers->{'rest-dspace-token'} = $self->dspace_token;
    }
    my $url = $self->_build_url(
        path => $self->_build_path(
            path_pattern => '/communities/:community_id',
            path_params => {
                'community_id' => $params{'community_id'}
            }
        ),
        query_params => {
            'userIP' => $params{'userIP'},
            'userAgent' => $params{'userAgent'},
            'xforwardedfor' => $params{'xforwardedfor'}
        }
    );
    my $transformed_entity = $params{entity};
    if (defined $transformed_entity) {
        my $request_content_type = $all_headers->{'Content-Type'};
        $request_content_type = '' if (!defined $request_content_type);
        if ($request_content_type =~ m,^application/json,) {
            $transformed_entity = encode_json($transformed_entity);
        }
    }
    $self->client->PUT($url, $transformed_entity, $all_headers);
    my $result = $self->_handle_response('PUT', $self->host.$url);

    return $result;
}

sub delete_community {
    my $self = shift;
    my %params = validated_hash(\@_,
        'headers' => { isa => 'HashRef', optional => 1 },
        'community_id' => { isa => 'Str' },
        'userIP' => { isa => 'Str', optional => 1 },
        'userAgent' => { isa => 'Str', optional => 1 },
        'xforwardedfor' => { isa => 'Str', optional => 1 }
    );

    my $all_headers = {};

    if (defined $params{headers}) {
        foreach (keys %{$params{headers}}) {
            $all_headers->{$_} = $params{headers}{$_};
        }
    }
    if (defined $self->dspace_token) {
        $all_headers->{'rest-dspace-token'} = $self->dspace_token;
    }
    my $url = $self->_build_url(
        path => $self->_build_path(
            path_pattern => '/communities/:community_id',
            path_params => {
                'community_id' => $params{'community_id'}
            }
        ),
        query_params => {
            'userIP' => $params{'userIP'},
            'userAgent' => $params{'userAgent'},
            'xforwardedfor' => $params{'xforwardedfor'}
        }
    );
    $self->client->DELETE($url, $all_headers);
    my $result = $self->_handle_response('DELETE', $self->host.$url);

    return $result;
}

sub get_community {
    my $self = shift;
    my %params = validated_hash(\@_,
        'headers' => { isa => 'HashRef', optional => 1 },
        'community_id' => { isa => 'Str' },
        'expand' => { isa => 'Str', optional => 1 },
        'userIP' => { isa => 'Str', optional => 1 },
        'userAgent' => { isa => 'Str', optional => 1 },
        'xforwardedfor' => { isa => 'Str', optional => 1 }
    );

    my $all_headers = {};

    if (defined $params{headers}) {
        foreach (keys %{$params{headers}}) {
            $all_headers->{$_} = $params{headers}{$_};
        }
    }
    if (defined $self->dspace_token) {
        $all_headers->{'rest-dspace-token'} = $self->dspace_token;
    }
    my $url = $self->_build_url(
        path => $self->_build_path(
            path_pattern => '/communities/:community_id',
            path_params => {
                'community_id' => $params{'community_id'}
            }
        ),
        query_params => {
            'expand' => $params{'expand'},
            'userIP' => $params{'userIP'},
            'userAgent' => $params{'userAgent'},
            'xforwardedfor' => $params{'xforwardedfor'}
        }
    );
    $self->client->GET($url, $all_headers);
    my $result = $self->_handle_response('GET', $self->host.$url);

    return $result;
}

sub delete_community_collection {
    my $self = shift;
    my %params = validated_hash(\@_,
        'headers' => { isa => 'HashRef', optional => 1 },
        'collection_id' => { isa => 'Str' },
        'community_id' => { isa => 'Str' },
        'userIP' => { isa => 'Str', optional => 1 },
        'userAgent' => { isa => 'Str', optional => 1 },
        'xforwardedfor' => { isa => 'Str', optional => 1 }
    );

    my $all_headers = {};

    if (defined $params{headers}) {
        foreach (keys %{$params{headers}}) {
            $all_headers->{$_} = $params{headers}{$_};
        }
    }
    if (defined $self->dspace_token) {
        $all_headers->{'rest-dspace-token'} = $self->dspace_token;
    }
    my $url = $self->_build_url(
        path => $self->_build_path(
            path_pattern => '/communities/:community_id/collections/:collection_id',
            path_params => {
                'collection_id' => $params{'collection_id'},
                'community_id' => $params{'community_id'}
            }
        ),
        query_params => {
            'userIP' => $params{'userIP'},
            'userAgent' => $params{'userAgent'},
            'xforwardedfor' => $params{'xforwardedfor'}
        }
    );
    $self->client->DELETE($url, $all_headers);
    my $result = $self->_handle_response('DELETE', $self->host.$url);

    return $result;
}

sub delete_community_community {
    my $self = shift;
    my %params = validated_hash(\@_,
        'headers' => { isa => 'HashRef', optional => 1 },
        'community_id' => { isa => 'Str' },
        'community_id2' => { isa => 'Str' },
        'userIP' => { isa => 'Str', optional => 1 },
        'userAgent' => { isa => 'Str', optional => 1 },
        'xforwardedfor' => { isa => 'Str', optional => 1 }
    );

    my $all_headers = {};

    if (defined $params{headers}) {
        foreach (keys %{$params{headers}}) {
            $all_headers->{$_} = $params{headers}{$_};
        }
    }
    if (defined $self->dspace_token) {
        $all_headers->{'rest-dspace-token'} = $self->dspace_token;
    }
    my $url = $self->_build_url(
        path => $self->_build_path(
            path_pattern => '/communities/:community_id/communities/:community_id2',
            path_params => {
                'community_id' => $params{'community_id'},
                'community_id2' => $params{'community_id2'}
            }
        ),
        query_params => {
            'userIP' => $params{'userIP'},
            'userAgent' => $params{'userAgent'},
            'xforwardedfor' => $params{'xforwardedfor'}
        }
    );
    $self->client->DELETE($url, $all_headers);
    my $result = $self->_handle_response('DELETE', $self->host.$url);

    return $result;
}

sub create_community {
    my $self = shift;
    my %params = validated_hash(\@_,
        'headers' => { isa => 'HashRef', optional => 1 },
        'userIP' => { isa => 'Str', optional => 1 },
        'userAgent' => { isa => 'Str', optional => 1 },
        'xforwardedfor' => { isa => 'Str', optional => 1 },
        'entity' => { isa => 'Item' }
    );

    my $all_headers = {};

    if (defined $params{headers}) {
        foreach (keys %{$params{headers}}) {
            $all_headers->{$_} = $params{headers}{$_};
        }
    }
    if (defined $self->dspace_token) {
        $all_headers->{'rest-dspace-token'} = $self->dspace_token;
    }
    my $url = $self->_build_url(
        path => $self->_build_path(
            path_pattern => '/communities',
            path_params => {
                
            }
        ),
        query_params => {
            'userIP' => $params{'userIP'},
            'userAgent' => $params{'userAgent'},
            'xforwardedfor' => $params{'xforwardedfor'}
        }
    );
    my $transformed_entity = $params{entity};
    if (defined $transformed_entity) {
        my $request_content_type = $all_headers->{'Content-Type'};
        $request_content_type = '' if (!defined $request_content_type);
        if ($request_content_type =~ m,^application/json,) {
            $transformed_entity = encode_json($transformed_entity);
        }
    }
    $self->client->POST($url, $transformed_entity, $all_headers);
    my $result = $self->_handle_response('POST', $self->host.$url);

    return $result;
}

sub get_communities {
    my $self = shift;
    my %params = validated_hash(\@_,
        'headers' => { isa => 'HashRef', optional => 1 },
        'expand' => { isa => 'Str', optional => 1 },
        'limit' => { isa => 'Int', optional => 1 },
        'offset' => { isa => 'Int', optional => 1 },
        'userIP' => { isa => 'Str', optional => 1 },
        'userAgent' => { isa => 'Str', optional => 1 },
        'xforwardedfor' => { isa => 'Str', optional => 1 }
    );

    my $all_headers = {};

    if (defined $params{headers}) {
        foreach (keys %{$params{headers}}) {
            $all_headers->{$_} = $params{headers}{$_};
        }
    }
    if (defined $self->dspace_token) {
        $all_headers->{'rest-dspace-token'} = $self->dspace_token;
    }
    my $url = $self->_build_url(
        path => $self->_build_path(
            path_pattern => '/communities',
            path_params => {
                
            }
        ),
        query_params => {
            'expand' => $params{'expand'},
            'limit' => $params{'limit'},
            'offset' => $params{'offset'},
            'userIP' => $params{'userIP'},
            'userAgent' => $params{'userAgent'},
            'xforwardedfor' => $params{'xforwardedfor'}
        }
    );
    $self->client->GET($url, $all_headers);
    my $result = $self->_handle_response('GET', $self->host.$url);

    return $result;
}

sub get_collection_items {
    my $self = shift;
    my %params = validated_hash(\@_,
        'headers' => { isa => 'HashRef', optional => 1 },
        'collection_id' => { isa => 'Str' },
        'expand' => { isa => 'Str', optional => 1 },
        'limit' => { isa => 'Int', optional => 1 },
        'offset' => { isa => 'Int', optional => 1 },
        'userIP' => { isa => 'Str', optional => 1 },
        'userAgent' => { isa => 'Str', optional => 1 },
        'xforwardedfor' => { isa => 'Str', optional => 1 }
    );

    my $all_headers = {};

    if (defined $params{headers}) {
        foreach (keys %{$params{headers}}) {
            $all_headers->{$_} = $params{headers}{$_};
        }
    }
    if (defined $self->dspace_token) {
        $all_headers->{'rest-dspace-token'} = $self->dspace_token;
    }
    my $url = $self->_build_url(
        path => $self->_build_path(
            path_pattern => '/collections/:collection_id/items',
            path_params => {
                'collection_id' => $params{'collection_id'}
            }
        ),
        query_params => {
            'expand' => $params{'expand'},
            'limit' => $params{'limit'},
            'offset' => $params{'offset'},
            'userIP' => $params{'userIP'},
            'userAgent' => $params{'userAgent'},
            'xforwardedfor' => $params{'xforwardedfor'}
        }
    );
    $self->client->GET($url, $all_headers);
    my $result = $self->_handle_response('GET', $self->host.$url);

    return $result;
}

sub add_collection_item {
    my $self = shift;
    my %params = validated_hash(\@_,
        'headers' => { isa => 'HashRef', optional => 1 },
        'collection_id' => { isa => 'Str' },
        'userIP' => { isa => 'Str', optional => 1 },
        'userAgent' => { isa => 'Str', optional => 1 },
        'xforwardedfor' => { isa => 'Str', optional => 1 },
        'entity' => { isa => 'Item' }
    );

    my $all_headers = {};

    if (defined $params{headers}) {
        foreach (keys %{$params{headers}}) {
            $all_headers->{$_} = $params{headers}{$_};
        }
    }
    if (defined $self->dspace_token) {
        $all_headers->{'rest-dspace-token'} = $self->dspace_token;
    }
    my $url = $self->_build_url(
        path => $self->_build_path(
            path_pattern => '/collections/:collection_id/items',
            path_params => {
                'collection_id' => $params{'collection_id'}
            }
        ),
        query_params => {
            'userIP' => $params{'userIP'},
            'userAgent' => $params{'userAgent'},
            'xforwardedfor' => $params{'xforwardedfor'}
        }
    );
    my $transformed_entity = $params{entity};
    if (defined $transformed_entity) {
        my $request_content_type = $all_headers->{'Content-Type'};
        $request_content_type = '' if (!defined $request_content_type);
        if ($request_content_type =~ m,^application/json,) {
            $transformed_entity = encode_json($transformed_entity);
        }
    }
    $self->client->POST($url, $transformed_entity, $all_headers);
    my $result = $self->_handle_response('POST', $self->host.$url);

    return $result;
}

sub delete_collection_item {
    my $self = shift;
    my %params = validated_hash(\@_,
        'headers' => { isa => 'HashRef', optional => 1 },
        'collection_id' => { isa => 'Str' },
        'item_id' => { isa => 'Str' },
        'userIP' => { isa => 'Str', optional => 1 },
        'userAgent' => { isa => 'Str', optional => 1 },
        'xforwardedfor' => { isa => 'Str', optional => 1 }
    );

    my $all_headers = {};

    if (defined $params{headers}) {
        foreach (keys %{$params{headers}}) {
            $all_headers->{$_} = $params{headers}{$_};
        }
    }
    if (defined $self->dspace_token) {
        $all_headers->{'rest-dspace-token'} = $self->dspace_token;
    }
    my $url = $self->_build_url(
        path => $self->_build_path(
            path_pattern => '/collections/:collection_id/items/:item_id',
            path_params => {
                'collection_id' => $params{'collection_id'},
                'item_id' => $params{'item_id'}
            }
        ),
        query_params => {
            'userIP' => $params{'userIP'},
            'userAgent' => $params{'userAgent'},
            'xforwardedfor' => $params{'xforwardedfor'}
        }
    );
    $self->client->DELETE($url, $all_headers);
    my $result = $self->_handle_response('DELETE', $self->host.$url);

    return $result;
}

sub find_collection_by_name {
    my $self = shift;
    my %params = validated_hash(\@_,
        'headers' => { isa => 'HashRef', optional => 1 },
        
    );

    my $all_headers = {};

    if (defined $params{headers}) {
        foreach (keys %{$params{headers}}) {
            $all_headers->{$_} = $params{headers}{$_};
        }
    }
    if (defined $self->dspace_token) {
        $all_headers->{'rest-dspace-token'} = $self->dspace_token;
    }
    my $url = $self->_build_url(
        path => $self->_build_path(
            path_pattern => '/collections/find-collection',
            path_params => {
                
            }
        ),
        query_params => {
            
        }
    );
    $self->client->POST($url, undef, $all_headers);
    my $result = $self->_handle_response('POST', $self->host.$url);

    return $result;
}

sub get_collection {
    my $self = shift;
    my %params = validated_hash(\@_,
        'headers' => { isa => 'HashRef', optional => 1 },
        'collection_id' => { isa => 'Str' },
        'expand' => { isa => 'Str', optional => 1 },
        'limit' => { isa => 'Int', optional => 1 },
        'offset' => { isa => 'Int', optional => 1 },
        'userIP' => { isa => 'Str', optional => 1 },
        'userAgent' => { isa => 'Str', optional => 1 },
        'xforwardedfor' => { isa => 'Str', optional => 1 }
    );

    my $all_headers = {};

    if (defined $params{headers}) {
        foreach (keys %{$params{headers}}) {
            $all_headers->{$_} = $params{headers}{$_};
        }
    }
    if (defined $self->dspace_token) {
        $all_headers->{'rest-dspace-token'} = $self->dspace_token;
    }
    my $url = $self->_build_url(
        path => $self->_build_path(
            path_pattern => '/collections/:collection_id',
            path_params => {
                'collection_id' => $params{'collection_id'}
            }
        ),
        query_params => {
            'expand' => $params{'expand'},
            'limit' => $params{'limit'},
            'offset' => $params{'offset'},
            'userIP' => $params{'userIP'},
            'userAgent' => $params{'userAgent'},
            'xforwardedfor' => $params{'xforwardedfor'}
        }
    );
    $self->client->GET($url, $all_headers);
    my $result = $self->_handle_response('GET', $self->host.$url);

    return $result;
}

sub delete_collection {
    my $self = shift;
    my %params = validated_hash(\@_,
        'headers' => { isa => 'HashRef', optional => 1 },
        'collection_id' => { isa => 'Str' },
        'userIP' => { isa => 'Str', optional => 1 },
        'userAgent' => { isa => 'Str', optional => 1 },
        'xforwardedfor' => { isa => 'Str', optional => 1 }
    );

    my $all_headers = {};

    if (defined $params{headers}) {
        foreach (keys %{$params{headers}}) {
            $all_headers->{$_} = $params{headers}{$_};
        }
    }
    if (defined $self->dspace_token) {
        $all_headers->{'rest-dspace-token'} = $self->dspace_token;
    }
    my $url = $self->_build_url(
        path => $self->_build_path(
            path_pattern => '/collections/:collection_id',
            path_params => {
                'collection_id' => $params{'collection_id'}
            }
        ),
        query_params => {
            'userIP' => $params{'userIP'},
            'userAgent' => $params{'userAgent'},
            'xforwardedfor' => $params{'xforwardedfor'}
        }
    );
    $self->client->DELETE($url, $all_headers);
    my $result = $self->_handle_response('DELETE', $self->host.$url);

    return $result;
}

sub update_collection {
    my $self = shift;
    my %params = validated_hash(\@_,
        'headers' => { isa => 'HashRef', optional => 1 },
        'collection_id' => { isa => 'Str' },
        'userIP' => { isa => 'Str', optional => 1 },
        'userAgent' => { isa => 'Str', optional => 1 },
        'xforwardedfor' => { isa => 'Str', optional => 1 },
        'entity' => { isa => 'Item' }
    );

    my $all_headers = {};

    if (defined $params{headers}) {
        foreach (keys %{$params{headers}}) {
            $all_headers->{$_} = $params{headers}{$_};
        }
    }
    if (defined $self->dspace_token) {
        $all_headers->{'rest-dspace-token'} = $self->dspace_token;
    }
    my $url = $self->_build_url(
        path => $self->_build_path(
            path_pattern => '/collections/:collection_id',
            path_params => {
                'collection_id' => $params{'collection_id'}
            }
        ),
        query_params => {
            'userIP' => $params{'userIP'},
            'userAgent' => $params{'userAgent'},
            'xforwardedfor' => $params{'xforwardedfor'}
        }
    );
    my $transformed_entity = $params{entity};
    if (defined $transformed_entity) {
        my $request_content_type = $all_headers->{'Content-Type'};
        $request_content_type = '' if (!defined $request_content_type);
        if ($request_content_type =~ m,^application/json,) {
            $transformed_entity = encode_json($transformed_entity);
        }
    }
    $self->client->PUT($url, $transformed_entity, $all_headers);
    my $result = $self->_handle_response('PUT', $self->host.$url);

    return $result;
}

sub get_collections {
    my $self = shift;
    my %params = validated_hash(\@_,
        'headers' => { isa => 'HashRef', optional => 1 },
        'expand' => { isa => 'Str', optional => 1 },
        'limit' => { isa => 'Int', optional => 1 },
        'offset' => { isa => 'Int', optional => 1 },
        'userIP' => { isa => 'Str', optional => 1 },
        'userAgent' => { isa => 'Str', optional => 1 },
        'xforwardedfor' => { isa => 'Str', optional => 1 }
    );

    my $all_headers = {};

    if (defined $params{headers}) {
        foreach (keys %{$params{headers}}) {
            $all_headers->{$_} = $params{headers}{$_};
        }
    }
    if (defined $self->dspace_token) {
        $all_headers->{'rest-dspace-token'} = $self->dspace_token;
    }
    my $url = $self->_build_url(
        path => $self->_build_path(
            path_pattern => '/collections',
            path_params => {
                
            }
        ),
        query_params => {
            'expand' => $params{'expand'},
            'limit' => $params{'limit'},
            'offset' => $params{'offset'},
            'userIP' => $params{'userIP'},
            'userAgent' => $params{'userAgent'},
            'xforwardedfor' => $params{'xforwardedfor'}
        }
    );
    $self->client->GET($url, $all_headers);
    my $result = $self->_handle_response('GET', $self->host.$url);

    return $result;
}


1;
