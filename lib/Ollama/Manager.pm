package Ollama::Manager;

use strict;
use warnings;
use v5.32.0;

use File::Spec  ();
use File::Which ();
use POSIX       qw( chmod close fork kill open setsid sleep unlink );
use Carp        qw( carp croak );
use Cwd         qw( abs_path );
use HTTP::Tiny  ();
use File::Temp  qw( tempfile );
use IPC::Run    qw( run );

# Official URL for the install script
use constant OLLAMA_INSTALL_URL => 'https://ollama.com/install.sh';

sub new {
    my $class = shift;
    my %args  = @_;
    my $self  = bless {}, $class;
    $self->_initialize(%args);
    return $self;
}

sub _initialize {
    my $self = shift;
    my %args = @_;

    $self->{config} = {
        ollama_path => $args{ollama_path},    # Explicit path override
        install_url => $args{install_url} || OLLAMA_INSTALL_URL,
        pid_file    => $args{pid_file}    || File::Spec->catfile( File::Spec->tmpdir, 'ollama.pid' ),
    };

    $self->_find_ollama();
}

sub _find_ollama {
    my $self = shift;

    # If explicit path provided, use it
    if ( my $path = $self->{config}{ollama_path} ) {
        if ( -x $path ) {
            $self->{ollama_path} = abs_path($path);
            return $self->{ollama_path};
        }
        carp "Specified ollama path '$path' is not executable";
    }

    # Try to find ollama in PATH
    if ( my $path = File::Which::which('ollama') ) {
        $self->{ollama_path} = $path;
        return $path;
    }

    return undef;
}

sub is_installed {
    my $self = shift;
    return defined $self->{ollama_path};
}

sub version {
    my $self = shift;

    croak "Ollama is not installed" unless $self->is_installed;

    my ( $stdout, $stderr );
    if ( run( [ $self->{ollama_path}, '--version' ], '>', \$stdout, '2>', \$stderr ) ) {
        chomp $stdout;
        return $stdout;
    }

    croak "Failed to get Ollama version: $stderr";
}

sub install {
    my $self = shift;
    my %args = @_;

    # Check platform
    croak "Installation is only supported on Unix-like systems"
        unless $^O =~ /^(linux|darwin|freebsd|netbsd|openbsd)$/;

    # If already installed and not forced, return success
    if ( $self->is_installed && !$args{force} ) {
        carp "Ollama is already installed";
        return 1;
    }

    carp "Installation requires appropriate system permissions";

    # Fetch install script
    my $http     = HTTP::Tiny->new;
    my $response = $http->get( $self->{config}{install_url} );

    croak "Failed to download install script: $response->{status} $response->{reason}"
        unless $response->{success};

    # Create temporary file for script
    my ( $fh, $tempfile ) = tempfile();
    print $fh $response->{content};
    close $fh;
    chmod 0755, $tempfile;

    # Execute install script
    my ( $stdout, $stderr );
    if ( run( [ 'sh', $tempfile ], '>', \$stdout, '2>', \$stderr ) ) {
        unlink $tempfile;
        $self->_find_ollama();
        return $self->is_installed;
    }

    unlink $tempfile;
    croak "Installation failed: $stderr";
}

sub start {
    my $self = shift;
    my %args = @_;

    croak "Ollama is not installed" unless $self->is_installed;

    # Check if already running
    if ( my $status = $self->status ) {
        return 1 if $status eq 'RUNNING';
    }

    # Start ollama serve in background
    my $pid = fork();
    croak "Failed to fork: $!" unless defined $pid;

    if ( $pid == 0 ) {

        # Child process
        setsid();
        exec( $self->{ollama_path}, 'serve' );
    }

    # Parent process
    # Store PID
    open( my $fh, '>', $self->{config}{pid_file} ) or croak "Failed to write PID file: $!";
    print $fh $pid;
    close $fh;

    # Wait a bit and verify process started
    sleep 1;
    return $self->status eq 'RUNNING';
}

sub stop {
    my $self = shift;
    my %args = @_;

    croak "Ollama is not installed" unless $self->is_installed;

    my $pid = $self->pid;
    return 1 unless $pid;    # Already stopped

    # Send SIGTERM
    kill 'TERM', $pid;

    # Wait for process to stop
    my $timeout = $args{timeout} || 10;
    my $waited  = 0;
    while ( $waited < $timeout ) {
        sleep 1;
        $waited++;
        return 1 unless kill 0, $pid;
    }

    # If still running, send SIGKILL
    if ( kill 0, $pid ) {
        kill 'KILL', $pid;
        carp "Had to forcefully kill Ollama process";
    }

    unlink $self->{config}{pid_file} if -e $self->{config}{pid_file};
    return 1;
}

sub restart {
    my $self = shift;
    my %args = @_;

    return 0 unless $self->stop(%args);
    return $self->start(%args);
}

sub status {
    my $self = shift;

    croak "Ollama is not installed" unless $self->is_installed;

    my $pid = $self->pid;
    return 'STOPPED' unless $pid;

    return kill( 0, $pid ) ? 'RUNNING' : 'STOPPED';
}

sub pid {
    my $self = shift;

    # Check PID file first
    if ( -e $self->{config}{pid_file} ) {
        open( my $fh, '<', $self->{config}{pid_file} ) or return undef;
        my $pid = <$fh>;
        close $fh;
        chomp $pid;
        return $pid if $pid =~ /^\d+$/ && kill( 0, $pid );
    }

    return undef;
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

=item pid_file

Path to store the PID file.

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

=item start(%args)

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

Returns the server status: 'RUNNING', 'STOPPED', or 'UNKNOWN'.

=item pid()

Returns the PID of the running Ollama server process, or undef if not running.

=back

=head1 AUTHOR

Paul Derscheid <me@paulderscheid.xyz>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut 
