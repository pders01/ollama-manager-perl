package Ollama::Manager;

use strict;
use warnings;
use 5.032000;

our $VERSION = '0.1.0';

use File::Which     ();
use POSIX           qw( kill );
use Carp            qw( carp croak );
use Cwd             qw( abs_path );
use HTTP::Tiny      ();
use File::Temp      qw( tempfile );
use Const::Fast     qw( const );
use English         qw( -no_match_vars );
use System::Command ();
use IO::Select      ();

# Official URL for the install script
const my $OLLAMA_INSTALL_URL  => 'https://ollama.com/install.sh';
const my $DEFAULT_CMD_TIMEOUT => 5;
const my $INSTALL_TIMEOUT     => 600;
const my $LISTEN_PORT         => 11_434;
const my $EXIT_CODE_SHIFT     => 8;
const my $FILE_PERMS          => 0o755;
const my $TIMEOUT_SECONDS     => 10;
const my $BUFFER_SIZE         => 8192;

sub new {
    my ( $class, %args ) = @_;
    my $self = bless {}, $class;
    $self->_initialize(%args);
    return $self;
}

sub _initialize {
    my ( $self, %args ) = @_;

    $self->{config} = {
        ollama_path => $args{ollama_path},
        install_url => $args{install_url} || $OLLAMA_INSTALL_URL,
    };

    $self->_find_ollama();
    return;
}

sub _find_ollama {
    my $self = shift;

    if ( my $path = $self->{config}{ollama_path} ) {
        if ( -x $path ) {
            $self->{ollama_path} = abs_path($path);
            return $self->{ollama_path};
        }
        carp "Specified ollama path '$path' is not executable";
    }

    if ( my $path = File::Which::which('ollama') ) {
        $self->{ollama_path} = $path;
        return $path;
    }

    return;
}

sub is_installed {
    my $self = shift;
    return defined $self->{ollama_path};
}

sub _run_cmd {
    my ( $self, $cmd_aryref, %opts ) = @_;
    my $timeout_seconds = $opts{timeout} // $DEFAULT_CMD_TIMEOUT;

    my $cmd;
    eval { $cmd = System::Command->new( @{$cmd_aryref} ); 1 } or return ( 0, q{}, "exec error: $EVAL_ERROR" );

    my $sel = IO::Select->new();
    $sel->add( $cmd->stdout );
    $sel->add( $cmd->stderr );

    my $out      = q{};
    my $err      = q{};
    my $end_time = time + $timeout_seconds;

    while (1) {
        last if $cmd->is_terminated;
        my $remaining = $end_time - time;
        if ( $remaining <= 0 ) {
            $cmd->signal('KILL');
            $cmd->close();
            return ( 0, $out, $err, 1 );
        }
        my @ready = $sel->can_read($remaining);
        for my $fh (@ready) {
            my $buffer;
            my $read = sysread $fh, $buffer, $BUFFER_SIZE;
            if ( defined $read && $read > 0 ) {
                if ( fileno($fh) == fileno $cmd->stdout ) {
                    $out .= $buffer;
                }
                else {
                    $err .= $buffer;
                }
            }
            else {
                $sel->remove($fh);
                close $fh or croak "Failed to close handle: $EVAL_ERROR";
            }
        }
        last if $sel->count == 0;
    }

    my $exit = $cmd->exit();
    $cmd->close();
    my $success = ( defined $exit && $exit == 0 ) ? 1 : 0;
    return ( $success, $out, $err, 0 );
}

sub version {
    my $self = shift;

    if ( !$self->is_installed ) {
        croak 'Ollama is not installed';
    }

    my ( $ok, $stdout, $stderr, $timed_out )
        = $self->_run_cmd( [ $self->{ollama_path}, '--version' ], timeout => $DEFAULT_CMD_TIMEOUT );

    if ($timed_out) {
        croak 'Timeout while getting Ollama version';
    }
    if ( !$ok ) {
        croak "Failed to get Ollama version: $stderr";
    }

    chomp $stdout;
    if ( !$stdout ) {
        return;
    }

    if ( $stdout =~ /^ollama\s+version\s+is\s+(\d+[.]\d+[.]\d+)/xms ) {
        return $1;
    }

    return $stdout;
}

sub install {
    my ( $self, %args ) = @_;

    if ( $OSNAME !~ /linux|darwin|freebsd|netbsd|openbsd/xms ) {
        croak 'Installation is only supported on Unix-like systems';
    }

    if ( $self->is_installed && !$args{force} ) {
        carp 'Ollama is already installed';
        return;
    }

    carp 'Installation requires appropriate system permissions';

    my $http     = HTTP::Tiny->new;
    my $response = $http->get( $self->{config}{install_url} );

    if ( !$response->{success} ) {
        croak "Failed to download install script: $response->{status} $response->{reason}";
    }

    my ( $fh, $tempfile ) = tempfile();
    my $printed = print {$fh} $response->{content};
    if ( !$printed ) {
        close $fh or croak 'Failed to write install script to temp file';
    }
    my $closed = close $fh or croak 'Failed to close install script temp file handle';
    if ( !$closed ) {
        croak 'Failed to close install script temp file handle';
    }
    chmod $FILE_PERMS, $tempfile;

    my ( $ok, undef, $stderr, $timed_out )
        = $self->_run_cmd( [ 'sh', $tempfile ], timeout => ( $args{timeout} // $INSTALL_TIMEOUT ) );
    unlink $tempfile;

    if ($timed_out) {
        croak 'Installation timed out';
    }
    if ( !$ok ) {
        croak "Installation failed: $stderr";
    }

    $self->_find_ollama();
    return $self->is_installed;
}

sub start {
    my $self = shift;

    if ( !$self->is_installed ) {
        croak 'Ollama is not installed';
    }

    if ( $self->status eq 'RUNNING' ) {
        return;
    }

    my $cmd;
    eval { $cmd = System::Command->new( $self->{ollama_path}, 'serve' ); 1 }
        or croak "Failed to start ollama serve: $EVAL_ERROR";

    # Detach by closing all handles; let external supervisor keep it alive
    for my $fh ( $cmd->stdin, $cmd->stdout, $cmd->stderr ) {
        eval { close $fh or carp "Failed to close handle: $EVAL_ERROR" }
            or carp "Failed to close handle: $EVAL_ERROR";
    }

    sleep 1;
    return $self->status eq 'RUNNING';
}

sub stop {
    my ( $self, %args ) = @_;

    if ( !$self->is_installed ) {
        croak 'Ollama is not installed';
    }

    my $pid = $self->pid;
    if ( !$pid ) {
        return 1;
    }

    kill 'TERM', $pid;

    my $timeout = $args{timeout} || $ENV{OLLAMA_MANAGER_STOP_TIMEOUT} || $TIMEOUT_SECONDS;
    my $waited  = 0;
    while ( $waited < $timeout ) {
        sleep 1;
        $waited++;
        if ( !kill 0, $pid ) {
            return 1;
        }
    }

    if ( kill 0, $pid ) {
        kill 'KILL', $pid;
        carp 'Had to forcefully kill Ollama process';
    }

    return 1;
}

sub restart {
    my ( $self, %args ) = @_;

    if ( !$self->stop(%args) ) {
        return;
    }

    return $self->start();
}

sub status {
    my $self = shift;

    if ( !$self->is_installed ) {
        croak 'Ollama is not installed';
    }

    if ( !$ENV{OLLAMA_MANAGER_DISABLE_HTTP} && $self->_http_is_alive() ) {
        return 'RUNNING';
    }

    my $pid = $self->pid;
    return defined $pid ? 'RUNNING' : 'STOPPED';
}

sub _http_is_alive {
    my ($self) = @_;
    my $http   = HTTP::Tiny->new( timeout => 2 );
    my $res    = $http->get('http://127.0.0.1:11434/api/version');
    return $res->{success} ? 1 : 0;
}

sub _is_ollama_serve_pid {
    my ( $self, $pid ) = @_;

    return 0 if !defined $pid || $pid !~ /^\d+$/xms;
    return 0 if !kill 0, $pid;

    my ( $ok_ps, $cmd ) = $self->_run_cmd( [ 'ps', '-p', $pid, '-o', 'command=' ], timeout => 2 );
    return 0 if !$ok_ps;
    my $lc = lc( $cmd // q{} );
    return ( $lc =~ /ollama/xms && $lc =~ /serve/xms ) ? 1 : 0;
}

sub _pid_via_proc_table {
    my ($self) = @_;

    my $have_ppt = eval { require Proc::ProcessTable; 1 };
    return if !$have_ppt;

    my $t = Proc::ProcessTable->new();
    for my $p ( @{ $t->table } ) {
        next if !$p || !$p->pid;
        my $cmnd = $p->cmndline // $p->fname // q{};
        my $lc   = lc $cmnd;
        next           if $lc !~ /ollama/xms || $lc !~ /serve/xms;
        return $p->pid if $self->_is_ollama_serve_pid( $p->pid );
    }
    return;
}

sub _pid_via_lsof {
    my ($self) = @_;

    my ( $ok_lsof, $lsof_out )
        = $self->_run_cmd( [ 'lsof', '-nP', qq{-iTCP:$LISTEN_PORT}, '-sTCP:LISTEN', '-Fp' ], timeout => 3 );
    return if !$ok_lsof || !$lsof_out;

    for my $line ( split /\n/xms, $lsof_out ) {
        my ($pid) = $line =~ /^p(\d+)/xms;
        next        if !$pid;
        return $pid if $self->_is_ollama_serve_pid($pid);
    }
    return;
}

sub _pid_via_pgrep {
    my ($self) = @_;

    my ( $ok_pgrep, $pgrep_out ) = $self->_run_cmd( [ 'pgrep', '-f', 'ollama serve' ], timeout => 2 );
    return if !$ok_pgrep || !$pgrep_out;

    my @pids = grep {/^\d+$/xms} split /\s+/xms, $pgrep_out;
    for my $pid (@pids) {
        return $pid if $self->_is_ollama_serve_pid($pid);
    }
    return;
}

sub pid {
    my $self = shift;

    if ( !$self->is_installed ) {
        croak 'Ollama is not installed';
    }

    my $pid = $self->_pid_via_proc_table();
    return $pid if defined $pid;

    $pid = $self->_pid_via_lsof();
    return $pid if defined $pid;

    $pid = $self->_pid_via_pgrep();
    return $pid if defined $pid;

    return;
}

sub _run_ollama_cmd {
    my ( $self, $subcmd, $fail_msg, $args, $arg_order ) = @_;

    if ( !$self->is_installed ) {
        croak 'Ollama is not installed';
    }

    my @cmd = ( $self->{ollama_path}, $subcmd );
    if ( $arg_order && ref $arg_order eq 'ARRAY' ) {
        for my $arg ( @{$arg_order} ) {
            if ( exists $args->{$arg} && defined $args->{$arg} ) {
                if ( ref $args->{$arg} eq 'ARRAY' ) {
                    CORE::push @cmd, @{ $args->{$arg} };
                }
                else {
                    CORE::push @cmd, $args->{$arg};
                }
            }
        }
    }

    # Always append extra_args if present and not already handled
    my $has_extra_args = grep { $_ eq 'extra_args' } @{ $arg_order // [] };
    if ( !$arg_order || !$has_extra_args ) {
        if ( $args->{extra_args} ) {
            CORE::push @cmd, @{ $args->{extra_args} };
        }
    }
    my ( $ok, $stdout, $stderr ) = $self->_run_cmd( \@cmd, timeout => $TIMEOUT_SECONDS );
    if ( !$ok ) {
        croak "$fail_msg: $stderr";
    }
    return $stdout;
}

sub create {
    my ( $self, %args ) = @_;
    return $self->_run_ollama_cmd( 'create', 'Failed to create model', \%args, [qw(modelfile extra_args)] );
}

sub show {
    my ( $self, %args ) = @_;
    return $self->_run_ollama_cmd( 'show', 'Failed to show model', \%args, [qw(model extra_args)] );
}

sub run_model {
    my ( $self, %args ) = @_;
    return $self->_run_ollama_cmd( 'run', 'Failed to run model', \%args, [qw(model extra_args)] );
}

sub stop_model {
    my ( $self, %args ) = @_;
    return $self->_run_ollama_cmd( 'stop', 'Failed to stop model', \%args, [qw(model extra_args)] );
}

sub pull {
    my ( $self, %args ) = @_;
    return $self->_run_ollama_cmd( 'pull', 'Failed to pull model', \%args, [qw(model extra_args)] );
}

sub push {    ## no critic (Subroutines::ProhibitBuiltinHomonyms)
    my ( $self, %args ) = @_;
    return $self->_run_ollama_cmd( 'push', 'Failed to push model', \%args, [qw(model extra_args)] );
}

sub list {
    my ( $self, %args ) = @_;
    return $self->_run_ollama_cmd( 'list', 'Failed to list models', \%args, [qw(extra_args)] );
}

sub ps {
    my ( $self, %args ) = @_;
    return $self->_run_ollama_cmd( 'ps', 'Failed to list running models', \%args, [qw(extra_args)] );
}

sub cp {
    my ( $self, %args ) = @_;
    return $self->_run_ollama_cmd( 'cp', 'Failed to copy model', \%args, [qw(src dest extra_args)] );
}

sub rm {
    my ( $self, %args ) = @_;
    return $self->_run_ollama_cmd( 'rm', 'Failed to remove model', \%args, [qw(model extra_args)] );
}

sub help {
    my ( $self, %args ) = @_;
    return $self->_run_ollama_cmd( 'help', 'Failed to get help', \%args, [qw(command extra_args)] );
}

1;

__END__

=head1 NAME

Ollama::Manager - Perl interface for managing Ollama installation and server process

=head1 SYNOPSIS

    use Ollama::Manager;
    
    my $ollama = Ollama::Manager->new();
    
    # Install Ollama if not present
    if (!$ollama->is_installed) {
        $ollama->install();
    }
    
    # Start the server
    $ollama->start();
    
    # Check status
    if ($ollama->status eq 'RUNNING') {
        print "Ollama is running (PID: " . $ollama->pid . ")\n";
    }
    
    # Stop the server
    $ollama->stop();


=head1 DESCRIPTION

Ollama::Manager provides a Perl interface for managing the Ollama application lifecycle,
including installation, updates, and controlling the server process.

=head1 METHODS

=over 4

=item new(%args)

Constructor. Accepts the following optional arguments:

=over 4

=item ollama_path

Explicit path to the ollama executable.

=item install_url

URL for the Ollama installation script.

=back

=item is_installed()

Returns true if Ollama is installed and accessible.

=item version()

Returns the installed Ollama version.

=item install(%args)

Installs Ollama. Accepts:

=over 4

=item force

Force reinstallation even if already installed.

=back

=item start()

Starts the Ollama server process.

=item stop(%args)

Stops the Ollama server process. Accepts:

=over 4

=item timeout

Seconds to wait for graceful shutdown before force killing.

=back

=item restart(%args)

Restarts the Ollama server process.

=item status()

Returns the server status: 'RUNNING' or 'STOPPED'.

=item pid()

Returns the PID of the running Ollama server process, or undef if not running.

=back

=head1 AUTHOR

Paul Derscheid <me@paulderscheid.xyz>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut 
