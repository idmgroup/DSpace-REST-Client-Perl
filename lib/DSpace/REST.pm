package DSpace::REST;

use strict;

use Modern::Perl;

=head1 VERSION

Version 0.1

=head1 DESCRIPTION

B<DSpace::REST::Client> - This is a REST client for DSpace.

=cut

our $VERSION = '0.1';

sub new {
    my $pack = shift;
    my $config = { @_ };
    my $dspace_version = $config->{dspace_version};
    if (defined $dspace_version) {
        delete $config->{dspace_version};
        if ($dspace_version < 6.0) {
            require DSpace::REST::ClientV5;
            return DSpace::REST::ClientV5->new($config);
        } else {
            die "Version $dspace_version of DSpace REST API not supported yet";
        }
    } else {
        require DSpace::REST::ClientV5;
        return DSpace::REST::ClientV5->new($config);
    }
}

1;
