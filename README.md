# DSpace::REST::Client

[![Build Status](https://travis-ci.org/idmgroup/DSpace-REST-Client-Perl.svg?branch=master)](https://travis-ci.org/idmgroup/DSpace-REST-Client-Perl) [![Coverage Status](https://coveralls.io/repos/idmgroup/DSpace-REST-Client-Perl/badge.svg?branch=master&service=github)](https://coveralls.io/github/idmgroup/DSpace-REST-Client-Perl?branch=master)

Perl REST Client for DSpace

## Description

This is a REST client which is dealing with the authentication token automatically. It is based on REST::Client;

## Build hints

### Update WADL

Get it from a running DSpace instance and put it in the ``res`` directory.

### Regenerate Client.pm

```
./bin/wadl2perl.pl res/application.wadl res/Client.pm.tt >| lib/DSpace/REST/Client.pm
```

