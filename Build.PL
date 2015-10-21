use strict;
use warnings;
use Module::Build;

my $class = Module::Build->subclass(
    class => "Module::Build::Custom",
    code => <<'SUBCLASS' );

sub ACTION_hudson_test {
    my $self = shift;

    $self->depends_on("build");
    # set hudson mode
    $self->{HUDSON_MODE} = 1;
    $self->generic_test(type => 'default');
}

sub do_tests {
  my $self = shift;

  # if we are not running for Hudson, just execute normal test routine (parent)
  $self->{HUDSON_MODE}
    or return $self->SUPER::do_tests($self, @_);

  # We are in Hudson mode, use TAP::Harness::JUnit
  my $tests = $self->find_test_files;
  if(@$tests) {
    $self->run_tap_harness_JUnit($tests);
  } else {
    $self->log_info("No tests defined.\n");
  }
}

sub run_tap_harness_JUnit {
  my ($self, $tests) = @_;

print "------ JUnit tap harness \n";
  require TAP::Harness::JUnit;

  my $harness = TAP::Harness::JUnit->new({
    xmlfile => 'hudson_test_output.xml',
    merge => 1,
    lib => [@INC],
    verbosity => $self->{properties}{verbose},
    switches  => [ $self->harness_switches ],
    %{ $self->tap_harness_args },
  })->runtests(@$tests);

}

SUBCLASS


my $builder = $class->new(
    module_name         => 'DSpace::REST::Client',
    license             => 'perl',
    dist_author         => q{Arnaud de Bossoreille <debossoreille@idm.fr>},
    dist_version_from   => 'lib/DSpace/REST/Client.pm',
    configure_requires => {
        'Module::Build' => 0
    },
    requires => {
        'JSON' => 0,
        'JSON::XS' => 0,
        'Modern::Perl' => 0,
        'Moose' => 0,
        'MooseX::Params::Validate' => 0,
        'REST::Client' => 0,
        'URI' => 0,
        'namespace::autoclean' => 0,
    },
    add_to_cleanup      => [ qw(hudson_test_output.xml t/output t/log t/MyLocalModule.pm t/test_master_file.txt t/initial_log.txt t/sandbox) ],
);


$builder->create_build_script();

