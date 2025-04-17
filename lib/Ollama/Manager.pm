package Ollama::Manager;

use strict;
use warnings;
use v5.32.0;

use File::Which ();
use POSIX       qw( kill );
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
        ollama_path => $args{ollama_path},                         # Explicit path override
        install_url => $args{install_url} || OLLAMA_INSTALL_URL,
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
    my $success = eval {
        local $SIG{ALRM} = sub { die "timeout\n" };
        alarm 5;    # 5 second timeout
        my $result = run( [ $self->{ollama_path}, '--version' ], '>', \$stdout, '2>', \$stderr );
        alarm 0;
        return $result;
    };

    if ($@) {
        if ( $@ eq "timeout\n" ) {
            croak "Timeout while getting Ollama version";
        }
        croak "Failed to execute ollama --version: $@";
    }

    if ( !$success ) {
        croak "Failed to get Ollama version: $stderr";
    }

    chomp $stdout;
    return $stdout if !$stdout;    # Return empty string if no output

    # Extract version number from output
    if ( $stdout =~ /^ollama version is (\d+\.\d+\.\d+)/ ) {
        return $1;
    }

    # If we can't parse the version, return the raw output
    return $stdout;
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

    croak "Ollama is not installed" unless $self->is_installed;

    # Check if already running
    return 1 if $self->status eq 'RUNNING';

    # Start ollama serve in background
    my $pid = fork();
    croak "Failed to fork: $!" unless defined $pid;

    if ( $pid == 0 ) {

        # Child process
        exec( $self->{ollama_path}, 'serve' );
        exit 1;    # Should never reach here
    }

    # Parent process - wait a bit and verify process started
    sleep 1;
    return $self->status eq 'RUNNING';
}

sub stop {
    my $self = shift;
    my %args = @_;

    croak "Ollama is not installed" unless $self->is_installed;

    # Get running server PID
    my $pid = $self->pid;
    return 1 unless $pid;    # Already stopped

    # Try graceful shutdown first
    kill 'TERM', $pid;

    # Wait for process to stop
    my $timeout = $args{timeout} || 10;
    my $waited  = 0;
    while ( $waited < $timeout ) {
        sleep 1;
        $waited++;
        return 1 unless kill( 0, $pid );
    }

    # If still running, force kill
    if ( kill( 0, $pid ) ) {
        kill 'KILL', $pid;
        carp "Had to forcefully kill Ollama process";
    }

    return 1;
}

sub restart {
    my $self = shift;
    my %args = @_;

    return 0 unless $self->stop(%args);
    return $self->start();
}

sub status {
    my $self = shift;

    croak "Ollama is not installed" unless $self->is_installed;

    # Use 'ollama ps' to check running status
    my ( $stdout, $stderr );
    if ( run( [ $self->{ollama_path}, 'ps' ], '>', \$stdout, '2>', \$stderr ) ) {
        return 'RUNNING' if $stdout =~ /ollama serve/;
    }

    return 'STOPPED';
}

sub pid {
    my $self = shift;

    croak "Ollama is not installed" unless $self->is_installed;

    # Use pgrep to find the server process
    my $pid = eval {
        local $SIG{ALRM} = sub { die "timeout\n" };
        alarm 5;    # 5 second timeout
        my $result = qx(pgrep -f 'ollama serve');
        alarm 0;
        return $result;
    };

    if ($@) {
        if ( $@ eq "timeout\n" ) {
            carp "Timeout while finding Ollama process";
            return;
        }
        carp "Error finding Ollama process: $@";
        return;
    }

    chomp $pid;
    return unless $pid && $pid =~ /^\d+$/;

    # Verify the process is still running and is actually ollama
    if ( kill( 0, $pid ) ) {
        my $cmd = qx(ps -p $pid -o command=);
        return $pid if $cmd && $cmd =~ /ollama serve/;
    }

    return;
}

# Additional Ollama CLI Methods

sub create {
    my ( $self, %args ) = @_;
    croak "Ollama is not installed" unless $self->is_installed;
    my @cmd = ( $self->{ollama_path}, 'create' );
    CORE::push @cmd, $args{modelfile}       if $args{modelfile};
    CORE::push @cmd, @{ $args{extra_args} } if $args{extra_args};
    my ( $stdout, $stderr );
    my $success = run( \@cmd, '>', \$stdout, '2>', \$stderr );
    croak "Failed to create model: $stderr" unless $success;
    return $stdout;
}

sub show {
    my ( $self, %args ) = @_;
    croak "Ollama is not installed" unless $self->is_installed;
    my @cmd = ( $self->{ollama_path}, 'show' );
    CORE::push @cmd, $args{model}           if $args{model};
    CORE::push @cmd, @{ $args{extra_args} } if $args{extra_args};
    my ( $stdout, $stderr );
    my $success = run( \@cmd, '>', \$stdout, '2>', \$stderr );
    croak "Failed to show model: $stderr" unless $success;
    return $stdout;
}

sub run_model {
    my ( $self, %args ) = @_;
    croak "Ollama is not installed" unless $self->is_installed;
    my @cmd = ( $self->{ollama_path}, 'run' );
    CORE::push @cmd, $args{model}           if $args{model};
    CORE::push @cmd, @{ $args{extra_args} } if $args{extra_args};
    my ( $stdout, $stderr );
    my $success = run( \@cmd, '>', \$stdout, '2>', \$stderr );
    croak "Failed to run model: $stderr" unless $success;
    return $stdout;
}

sub stop_model {
    my ( $self, %args ) = @_;
    croak "Ollama is not installed" unless $self->is_installed;
    my @cmd = ( $self->{ollama_path}, 'stop' );
    CORE::push @cmd, $args{model}           if $args{model};
    CORE::push @cmd, @{ $args{extra_args} } if $args{extra_args};
    my ( $stdout, $stderr );
    my $success = run( \@cmd, '>', \$stdout, '2>', \$stderr );
    croak "Failed to stop model: $stderr" unless $success;
    return $stdout;
}

sub pull {
    my ( $self, %args ) = @_;
    croak "Ollama is not installed" unless $self->is_installed;
    my @cmd = ( $self->{ollama_path}, 'pull' );
    CORE::push @cmd, $args{model}           if $args{model};
    CORE::push @cmd, @{ $args{extra_args} } if $args{extra_args};
    my ( $stdout, $stderr );
    my $success = run( \@cmd, '>', \$stdout, '2>', \$stderr );
    croak "Failed to pull model: $stderr" unless $success;
    return $stdout;
}

sub push {
    my ( $self, %args ) = @_;
    croak "Ollama is not installed" unless $self->is_installed;
    my @cmd = ( $self->{ollama_path}, 'push' );
    CORE::push @cmd, $args{model}           if $args{model};
    CORE::push @cmd, @{ $args{extra_args} } if $args{extra_args};
    my ( $stdout, $stderr );
    my $success = run( \@cmd, '>', \$stdout, '2>', \$stderr );
    croak "Failed to push model: $stderr" unless $success;
    return $stdout;
}

sub list {
    my ( $self, %args ) = @_;
    croak "Ollama is not installed" unless $self->is_installed;
    my @cmd = ( $self->{ollama_path}, 'list' );
    CORE::push @cmd, @{ $args{extra_args} } if $args{extra_args};
    my ( $stdout, $stderr );
    my $success = run( \@cmd, '>', \$stdout, '2>', \$stderr );
    croak "Failed to list models: $stderr" unless $success;
    return $stdout;
}

sub ps {
    my ( $self, %args ) = @_;
    croak "Ollama is not installed" unless $self->is_installed;
    my @cmd = ( $self->{ollama_path}, 'ps' );
    CORE::push @cmd, @{ $args{extra_args} } if $args{extra_args};
    my ( $stdout, $stderr );
    my $success = run( \@cmd, '>', \$stdout, '2>', \$stderr );
    croak "Failed to list running models: $stderr" unless $success;
    return $stdout;
}

sub cp {
    my ( $self, %args ) = @_;
    croak "Ollama is not installed" unless $self->is_installed;
    my @cmd = ( $self->{ollama_path}, 'cp' );
    CORE::push @cmd, $args{src}             if $args{src};
    CORE::push @cmd, $args{dest}            if $args{dest};
    CORE::push @cmd, @{ $args{extra_args} } if $args{extra_args};
    my ( $stdout, $stderr );
    my $success = run( \@cmd, '>', \$stdout, '2>', \$stderr );
    croak "Failed to copy model: $stderr" unless $success;
    return $stdout;
}

sub rm {
    my ( $self, %args ) = @_;
    croak "Ollama is not installed" unless $self->is_installed;
    my @cmd = ( $self->{ollama_path}, 'rm' );
    CORE::push @cmd, $args{model}           if $args{model};
    CORE::push @cmd, @{ $args{extra_args} } if $args{extra_args};
    my ( $stdout, $stderr );
    my $success = run( \@cmd, '>', \$stdout, '2>', \$stderr );
    croak "Failed to remove model: $stderr" unless $success;
    return $stdout;
}

sub help {
    my ( $self, %args ) = @_;
    croak "Ollama is not installed" unless $self->is_installed;
    my @cmd = ( $self->{ollama_path}, 'help' );
    CORE::push @cmd, $args{command}         if $args{command};
    CORE::push @cmd, @{ $args{extra_args} } if $args{extra_args};
    my ( $stdout, $stderr );
    my $success = run( \@cmd, '>', \$stdout, '2>', \$stderr );
    croak "Failed to get help: $stderr" unless $success;
    return $stdout;
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

=item create(%args)

Creates a new model. Accepts:

=over 4

=item modelfile

Path to the model file.

=item extra_args

Array reference of additional arguments to pass to the 'create' command.

=back

=item show(%args)

Displays information about a model. Accepts:

=over 4

=item model

Name of the model to show.

=item extra_args

Array reference of additional arguments to pass to the 'show' command.

=back

=item run_model(%args)

Runs a model. Accepts:

=over 4

=item model

Name of the model to run.

=item extra_args

Array reference of additional arguments to pass to the 'run' command.

=back

=item stop_model(%args)

Stops a running model. Accepts:

=over 4

=item model

Name of the model to stop.

=item extra_args

Array reference of additional arguments to pass to the 'stop' command.

=back

=item pull(%args)

Pulls a model from a repository. Accepts:

=over 4

=item model

Name of the model to pull.

=item extra_args

Array reference of additional arguments to pass to the 'pull' command.

=back

=item push(%args)

Pushes a model to a repository. Accepts:

=over 4

=item model

Name of the model to push.

=item extra_args

Array reference of additional arguments to pass to the 'push' command.

=back

=item list(%args)

Lists available models. Accepts:

=over 4

=item extra_args

Array reference of additional arguments to pass to the 'list' command.

=back

=item ps(%args)

Lists running models. Accepts:

=over 4

=item extra_args

Array reference of additional arguments to pass to the 'ps' command.

=back

=item cp(%args)

Copies a model. Accepts:

=over 4

=item src

Source model name.

=item dest

Destination model name.

=item extra_args

Array reference of additional arguments to pass to the 'cp' command.

=back

=item rm(%args)

Removes a model. Accepts:

=over 4

=item model

Name of the model to remove.

=item extra_args

Array reference of additional arguments to pass to the 'rm' command.

=back

=item help(%args)

Displays help for a command. Accepts:

=over 4

=item command

Name of the command to display help for.

=item extra_args

Array reference of additional arguments to pass to the 'help' command.

=back

=back

=head1 AUTHOR

Paul Derscheid <me@paulderscheid.xyz>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut 
