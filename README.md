# DSpace::REST::Client

[![Build Status](https://travis-ci.org/idmgroup/DSpace-REST-Client-Perl.svg?branch=master)](https://travis-ci.org/idmgroup/DSpace-REST-Client-Perl) [![Coverage Status](https://coveralls.io/repos/idmgroup/DSpace-REST-Client-Perl/badge.svg?branch=master&service=github)](https://coveralls.io/github/idmgroup/DSpace-REST-Client-Perl?branch=master)

Perl REST Client for DSpace

## Description

This is a REST client which is dealing with the authentication token automatically. It is based on REST::Client;

## Usage

```
use DSpace::REST;

# create a new client for the latest released version of dspace
my $dspace = DSpace::REST->new(
    'host' => 'https://demo.dspace.org/rest'
);

# self signed certificate
my $ua = $dspace->client->getUseragent();
$ua->ssl_opts(SSL_fingerprint => 'sha256$9d9f9e072e4edfd6b0a16f87229f2634cc0c480d201272c0ba7b8a0b7defacad');

# log in (the token will be remembered)
$dspace->login(
    entity => {
        email => '********',
        password => '********'
    },
    headers => {
        'Content-Type' => 'application/json'
    }
);

# list the communities
my $slice = $dspace->get_communities(
    limit => 20,
    offset => 0,
    headers => {
        'Accept' => 'application/json'
    }
);

foreach my $com (@$slice) {
    print $com->{name}."\n";
}

# create a new client for a specific version of dspace
my $dspace_v5 = DSpace::REST->new(
    'dspace_version' => 5.3,
    'host' => 'https://demo.dspace.org/rest'
);

```

## Build hints

### Update WADL

Get it from a running DSpace instance and put it in the ``res`` directory.

### Regenerate Client.pm

```
$ ./bin/wadl2perl.pl res/dspace-5_x/application.wadl res/dspace-5_x/Client.pm.tt >| lib/DSpace/REST/ClientV5.pm
```

