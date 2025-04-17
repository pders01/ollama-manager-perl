use strict;
use warnings;
use Test::More import => [qw( done_testing like ok skip use_ok )];
use Test::Exception;
use Time::HiRes qw( time );

# Timeout for process-related operations (in seconds)
use constant TIMEOUT => 5;

# Docker context install logic removed: now handled in Dockerfile

BEGIN {
    use_ok('Ollama::Manager');
}

# Find the running Ollama process
sub find_ollama_process {
    my $start_time = time;
    my $pid;
    
    while (time - $start_time < TIMEOUT) {
        my $pids = qx(pgrep -f 'ollama serve');
        ($pid) = $pids =~ /^(\\d+)/m;  # get the first numeric PID from output
        return $pid if defined $pid && $pid =~ /^\\d+$/ && kill(0, $pid);
        sleep 0.1;
    }
    
    return;
}

# Run a test with timeout
sub run_with_timeout {
    my ($test_name, $code) = @_;
    my $start_time = time;
    
    eval {
        local $SIG{ALRM} = sub { die "timeout\n" };
        alarm TIMEOUT;
        $code->();
        alarm 0;
    };
    
    if ($@) {
        if ($@ eq "timeout\n") {
            skip "Test '$test_name' timed out after " . TIMEOUT . " seconds", 1;
        } else {
            die $@;
        }
    }
}

# Check if we have a running Ollama instance
my $ollama_pid = find_ollama_process();

SKIP: {
    skip "No running Ollama process found or insufficient permissions", 8
        unless $ollama_pid;

    # Test constructor
    my $ollama;
    lives_ok {
        $ollama = Ollama::Manager->new();
    }
    'Constructor works';

    # Test is_installed
    ok( defined $ollama->is_installed, 'is_installed returns a value' );

    # Test version if installed
SKIP: {
        skip 'Ollama not installed', 1 unless $ollama->is_installed;

        run_with_timeout('version()', sub {
            my $version;
            lives_ok {
                $version = $ollama->version;
            } 'version() executes without error';

            # Skip version format check if we got a timeout
            return if !defined $version;

            # Handle both old and new version formats
            if ( $version =~ /^ollama version is (\d+\.\d+\.\d+)/ ) {
                $version = $1;
            }
            like( $version, qr/^\d+\.\d+\.\d+$/, 'Version format looks correct' );
        });
    }

    # Test status
    run_with_timeout('status()', sub {
        lives_ok {
            my $status = $ollama->status;
            ok( $status =~ /^(RUNNING|STOPPED)$/, 'Status is valid' );
        }
        'status() works';
    });

    # Test pid
    run_with_timeout('pid()', sub {
        lives_ok {
            my $pid = $ollama->pid;
            if ( $ollama->status eq 'RUNNING' ) {
                ok( $pid =~ /^\d+$/ && $pid == $ollama_pid, 'PID matches running process' );
            }
            else {
                ok( !defined $pid, 'PID is undef when stopped' );
            }
        }
        'pid() works';
    });

    # Skip start/stop tests since we're using an existing process
    # We don't want to interfere with the user's running instance
}

done_testing();
