package Ollama::Service::Systemd;

use strict;
use warnings;
use 5.032000;

use Carp        qw( croak );
use Const::Fast qw( const );

const my $SYSTEMD_UNIT    => 'ollama';
const my $SYSTEMD_SCOPE   => 'user';
const my $SYSTEMD_TIMEOUT => 5;

# Simple systemd service adapter. Delegates process execution to
# Ollama::Manager->_run_cmd for consistency and timeouts.

sub new {
    my ( $class, %args ) = @_;
    my $self = bless {
        unit    => $args{unit}    || $SYSTEMD_UNIT,
        scope   => $args{scope}   || $SYSTEMD_SCOPE,     # 'user' or 'system'
        timeout => $args{timeout} || $SYSTEMD_TIMEOUT,
    }, $class;
    return $self;
}

sub _systemctl_cmd {
    my ($self) = @_;
    return $self->{scope} eq 'system' ? ['systemctl'] : [ 'systemctl', '--user' ];
}

sub start {
    my ( $self, $manager ) = @_;
    my @cmd = ( @{ $self->_systemctl_cmd }, 'start', $self->{unit} );
    my ( $ok, undef, $err ) = $manager->_run_cmd( \@cmd, timeout => $self->{timeout} );
    if ( !$ok ) {
        croak "systemd start failed: $err";
    }
    return 1;
}

sub stop {
    my ( $self, $manager ) = @_;
    my @cmd = ( @{ $self->_systemctl_cmd }, 'stop', $self->{unit} );
    my ( $ok, undef, $err ) = $manager->_run_cmd( \@cmd, timeout => $self->{timeout} );
    if ( !$ok ) {
        croak "systemd stop failed: $err";
    }
    return 1;
}

sub status {
    my ( $self, $manager ) = @_;
    my @cmd = ( @{ $self->_systemctl_cmd }, 'is-active', $self->{unit} );
    my ( $ok, $out ) = $manager->_run_cmd( \@cmd, timeout => $self->{timeout} );
    $out =~ s/\s+\z//smx;
    return ( $ok && $out eq 'active' ) ? 'RUNNING' : 'STOPPED';
}

sub pid {
    my ( $self, $manager ) = @_;
    my @cmd = ( @{ $self->_systemctl_cmd }, 'show', '-p', 'MainPID', '--value', $self->{unit} );
    my ( $ok, $out ) = $manager->_run_cmd( \@cmd, timeout => $self->{timeout} );
    return if !$ok;
    $out =~ s/\s+\z//smx;
    if ( !$out || $out eq '0' ) {
        return;
    }
    if ( $out =~ /^\d+$/smx ) {
        return $out;
    }
    return;
}

1;

__END__

=head1 NAME

Ollama::Service::Systemd - systemd adapter for managing the Ollama service

=head1 SYNOPSIS

  use Ollama::Service::Systemd;
  my $svc = Ollama::Service::Systemd->new(unit => 'ollama', scope => 'user');
  $svc->start($manager);

=head1 DESCRIPTION

Provides start/stop/status/pid by invoking systemctl. Intended to be injected
into C<Ollama::Manager> via the C<service> argument.



