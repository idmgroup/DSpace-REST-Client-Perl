#!/usr/bin/perl

use strict;

use LWP::Simple;
use Storable qw(dclone);
use String::CamelCase qw(decamelize);
use XML::LibXML;

my $wadl_file = shift;

sub to_perl_type {
    my $xs_type = shift;
    if ($xs_type eq 'xs:string') {
        return 'Str';
    } elsif ($xs_type eq 'xs:int') {
        return 'Int';
    } else {
        die $xs_type;
    }
}

my $xpc = XML::LibXML::XPathContext->new;
$xpc->registerNs('wadl', 'http://wadl.dev.java.net/2009/02');

sub transform_element {
    my $element = shift;
    $element = uc(substr($element, 0, 1)).substr($element, 1, length($element) - 1);
    $element =~ s/Resourcepolicy/ResourcePolicy/g;
    $element =~ s/Metadataentry/MetadataEntry/g;
    return $element;
}

my %custom_return_types;
$custom_return_types{'test'} = 'String';
$custom_return_types{'status'} = 'Status';
$custom_return_types{'login'} = 'String';
$custom_return_types{'logout'} = 'Void';
$custom_return_types{'sayHtmlHello'} = 'String';
$custom_return_types{'getBitstreamData'} = 'byte[]';
$custom_return_types{''} = '';

sub get_return_type {
    my ($method) = @_;
    my $id = $method->getAttribute('id');
    my $type = $custom_return_types{$id};
    if (defined $type) {
        return $type;
    }

    my $id2 = $id;
    $id2 =~ s/By[A-Za-z]+$//;
    my ($prefix, $suffix);
    if (($prefix, $suffix) = $id2 =~ m/^([a-z]+).*([A-Z][a-z]+)$/) {
        if ($prefix eq 'get' || $prefix eq 'find') {
            if ($suffix =~ m/s$/) {
                my $singular = substr($suffix, 0, length($suffix) - 1);
                $singular =~ s/ie$/y/;
                $singular =~ s/^Metadata$/MetadataEntry/;
                $singular =~ s/^Policy$/ResourcePolicy/;
                return $singular.'[]';
            } else {
                my $singular = $suffix;
                $singular =~ s/ie$/y/;
                $singular =~ s/^Metadata$/MetadataEntry/;
                $singular =~ s/^Policy$/ResourcePolicy/;
                return $singular;
            }
        } elsif ($prefix eq 'add' || $prefix eq 'create') {
            my $response_representation = $xpc->find('wadl:response/wadl:representation[1]', $method)->[0];
            if (defined $response_representation) {
                my $element = $response_representation->getAttribute('element');
                if (defined $element && $element ne '') {
                    $element = transform_element($element);
                    return $element;
                } else {
                    print STDERR "response $id\n";
                    return 'Void';
                }
            }
        } elsif ($prefix eq 'update' || $prefix eq 'delete') {
            return 'Void';
        }
    }

    die $id;
}

my $parser = XML::LibXML->new();

my $wadl = $parser->parse_file($wadl_file) or die;

sub traverse_resources {
    my ($node, $parent_path) = @_;
    $parent_path =~ s,/+$,,;
    my $resources = $xpc->find('wadl:resource', $node);
    foreach my $resource (@$resources) {
        my $path = $resource->getAttribute('path');
        $path =~ s,^/+,,;
        my $full_path = $parent_path.'/'.$path;
        my $path_params = $xpc->find('wadl:param', $resource);
        traverse_resources($resource, $parent_path.'/'.$path);
        traverse_methods($resource, $full_path, $path_params);
    }
}

sub traverse_methods {
    my ($resource, $full_path, $path_params) = @_;
    my $methods = $xpc->find('wadl:method', $resource);
    foreach my $method (@$methods) {
        my $return_type = get_return_type($method);

        my $method_name = $xpc->findvalue('@id', $method);
        my $decam_method_name = decamelize($method_name);

        my $subroutine = {
            params_strs => [],
            path_params => [],
            query_params => []
        };

        my $params = $xpc->find('wadl:request/wadl:param', $method);
        foreach my $param (@$path_params) {
            my $name = $param->getAttribute('name');
            push @{$subroutine->{params_strs}}, "'$name' => { isa => '".to_perl_type($param->getAttribute('type'))."' }";
            push @{$subroutine->{path_params}}, "'$name' => \$params{'$name'}";
        }
        foreach my $param (@$params) {
            my $name = $param->getAttribute('name');
            push @{$subroutine->{params_strs}}, "'$name' => { isa => '".to_perl_type($param->getAttribute('type'))."', optional => 1 }";
            push @{$subroutine->{query_params}}, "'$name' => \$params{'$name'}";
        }

        my $method_verb = $method->getAttribute('name');

        my $request_entity = '';
        if ($method_verb eq 'PUT' || $method_verb eq 'PATCH' || $method_verb eq 'POST') {
            $request_entity = ', undef';
        }
        my $request_representation = $xpc->find('wadl:request/wadl:representation[1]', $method)->[0];
        if (defined $request_representation) {
            my $element = $request_representation->getAttribute('element');
            my $request_media_type = $request_representation->getAttribute('mediaType');
            if (defined $element && $element ne '') {
                $element = transform_element($element);
                push @{$subroutine->{params_strs}}, "'entity' => { isa => 'Item' }";
                $request_entity = ', $transformed_entity';
            } elsif ($request_media_type eq '*/*') {
                push @{$subroutine->{params_strs}}, "'entity' => { isa => 'Item' }";
                $request_entity = ', $transformed_entity';
            }
        }

        my $pre_call_code = '';
        my $post_call_code = '';
        if ($method_name eq 'login') {
            $pre_call_code = <<EOF
        # Logout just in case.
        if (defined \$self->dspace_token) {
            eval {
                \$self->logout();
            };
            warn $@ if ($@);
            \$self->dspace_token(undef);
        }
        # Login
EOF
            ;
            $post_call_code = <<EOF
        \$self->dspace_token(\$result);
EOF
            ;
        }

        my $fp = $full_path;
        $fp =~ s,/\{([^/\}]+)\},/:$1,g;

        my $params_str = join ",\n        ", @{$subroutine->{params_strs}};
        my $path_params_str = "{\n                ".(join ",\n                ", @{$subroutine->{path_params}})."\n            }";
        my $query_params_str = "{\n            ".(join ",\n            ", @{$subroutine->{query_params}})."\n        }";

        print <<EOF
sub $decam_method_name {
    my \$self = shift;
    my %params = validated_hash(\\\@_,
        'headers' => { isa => 'HashRef', optional => 1 },
        $params_str
    );
$pre_call_code
    my \$all_headers = {};
    if (defined \$params{headers}) {
        foreach (keys \%{\$params{headers}}) {
            \$all_headers->{\$_} = \$params{headers}{\$_};
        }
    }
    if (defined \$self->dspace_token) {
        \$all_headers->{'rest-dspace-token'} = \$self->dspace_token;
    }
    my \$url = \$self->_build_url(
        path => \$self->_build_path(
            path_pattern => '$fp',
            path_params => $path_params_str
        ),
        query_params => $query_params_str
    );
    my \$transformed_entity = \$params{entity};
    if (defined \$transformed_entity) {
        my \$request_content_type = \$all_headers->{'Content-Type'};
        \$request_content_type = '' if (!defined \$request_content_type);
        if (\$request_content_type eq 'application/json') {
            \$transformed_entity = to_json(\$transformed_entity);
        }
    }
    \$self->client->$method_verb(\$url$request_entity, \$all_headers);
    my \$result = \$self->_handle_response('$method_verb', \$self->host.\$url);
$post_call_code
    return \$result;
}

EOF
        ;
    }
}

my $line;
while($line = <>) {
    if ($line =~ m/^\s*\[\% generated_code \%\]\s*$/) {
        traverse_resources($xpc->find('/wadl:application/wadl:resources', $wadl)->[0], '');
    } else {
        print $line;
    }
}

