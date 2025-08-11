package Ollama::Service::Launchd;

use strict;
use warnings;
use 5.032000;

use Carp        qw( croak );
use English     qw( -no_match_vars );
use Const::Fast qw( const );

const my $LAUNCHD_TIMEOUT => 5;

# launchd adapter for macOS. Uses `launchctl` to manage a LaunchDaemon/LaunchAgent.
# Configure with the launchd label and a domain scope (gui/$UID or system).

sub new {
    my ( $class, %args ) = @_;
    my $uid    = defined $args{uid} ? $args{uid} : $EFFECTIVE_USER_ID;
    my $scope  = $args{scope} // 'gui';                                  # 'gui' or 'system'
    my $domain = $scope eq 'system' ? 'system' : sprintf 'gui/%d', $uid;
    my $self   = bless {
        label   => $args{label},                                         # undef means auto-detect
        domain  => $domain,
        timeout => $args{timeout} || $LAUNCHD_TIMEOUT,
    }, $class;
    return $self;
}

sub _target {
    my ($self) = @_;
    return join q{/}, $self->{domain}, $self->{label};
}

sub _discover_labels {
    my ( $self, $manager ) = @_;
    my ( $ok,   $out )     = $manager->_run_cmd( [ 'launchctl', 'list' ], timeout => $self->{timeout} );
    return [] if !$ok || !$out;

    my @candidates;
    for my $line ( split /\n/smx, $out ) {

        # Expected format: PID\tStatus\tLabel
        my ( $pid, undef, $label ) = split /\s+/smx, $line, 3;
        next if !$label || $label !~ /ollama/smxi;
        push @candidates, { label => $label, pid_active => ( defined $pid && $pid ne q{-} && $pid =~ /^\d+$/smx ) ? 1 : 0 };
    }

    # Prefer active processes first, then known common labels
    my @known_order = ( 'application.com.electron.ollama', 'homebrew.mxcl.ollama', 'com.ollama.ollama', );

    @candidates = reverse sort {
        ( $a->{pid_active} <=> $b->{pid_active} )
            || reverse _label_rank( $a->{label}, \@known_order ) <=> _label_rank( $b->{label}, \@known_order )
    } @candidates;

    my @labels = map { $_->{label} } @candidates;
    return \@labels;
}

sub _label_rank {
    my ( $label, $order ) = @_;
    for my $i ( 0 .. $#{$order} ) {
        return $i if index( $label, $order->[$i] ) >= 0;
    }
    return scalar @{$order};
}

sub _targets_for_actions {
    my ( $self, $manager ) = @_;
    if ( defined $self->{label} && length $self->{label} ) {
        return [ $self->_target ];
    }
    my $labels = $self->_discover_labels($manager);
    return [ map { join q{/}, $self->{domain}, $_ } @{$labels} ];
}

sub start {
    my ( $self, $manager ) = @_;
    my $targets = $self->_targets_for_actions($manager);
    if ( @{$targets} == 0 ) {    # fallback to default label if none discovered
        $self->{label} = 'com.ollama.ollama';
        $targets = [ $self->_target ];
    }
    for my $t ( @{$targets} ) {
        my @cmd = ( 'launchctl', 'kickstart', '-k', $t );
        my ( $ok, undef, $err ) = $manager->_run_cmd( \@cmd, timeout => $self->{timeout} );
        return 1 if $ok;

        # try next candidate
    }
    croak 'launchd start failed for all candidate labels';
}

sub stop {
    my ( $self, $manager ) = @_;
    my $targets = $self->_targets_for_actions($manager);
    if ( @{$targets} == 0 ) {
        $self->{label} = 'com.ollama.ollama';
        $targets = [ $self->_target ];
    }
    for my $t ( @{$targets} ) {
        my @cmd = ( 'launchctl', 'stop', $t );
        my ( $ok, undef, $err ) = $manager->_run_cmd( \@cmd, timeout => $self->{timeout} );
        return 1 if $ok;
    }
    croak 'launchd stop failed for all candidate labels';
}

sub status {
    my ( $self, $manager ) = @_;
    my $targets = $self->_targets_for_actions($manager);
    if ( @{$targets} == 0 ) {
        $self->{label} = 'com.ollama.ollama';
        $targets = [ $self->_target ];
    }
    for my $t ( @{$targets} ) {
        my @cmd = ( 'launchctl', 'print', $t );
        my ( $ok, $out ) = $manager->_run_cmd( \@cmd, timeout => $self->{timeout} );
        next             if !$ok || !$out;
        return 'RUNNING' if $out =~ /^\s*state\s*=\s*running/smx;
        return 'RUNNING' if $out =~ /^\s*pid\s*=\s*\d+/smx;
    }
    return 'STOPPED';
}

sub pid {
    my ( $self, $manager ) = @_;
    my $targets = $self->_targets_for_actions($manager);
    if ( @{$targets} == 0 ) {
        $self->{label} = 'com.ollama.ollama';
        $targets = [ $self->_target ];
    }
    for my $t ( @{$targets} ) {
        my @cmd = ( 'launchctl', 'print', $t );
        my ( $ok, $out ) = $manager->_run_cmd( \@cmd, timeout => $self->{timeout} );
        next if !$ok || !$out;
        if ( $out =~ /^\s*pid\s*=\s*(\d+)/smx ) {
            return $1;
        }
    }
    return;
}

1;

__END__

=head1 NAME

Ollama::Service::Launchd - launchd adapter for managing the Ollama service on macOS

=head1 SYNOPSIS

  use Ollama::Service::Launchd;
  my $svc = Ollama::Service::Launchd->new(label => 'com.ollama.ollama', scope => 'gui');
  $svc->start($manager);

=head1 DESCRIPTION

Provides start/stop/status/pid using C<launchctl> for macOS. Intended for dependency
injection into C<Ollama::Manager>.


