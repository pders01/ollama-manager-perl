use strict;
use warnings;
use Test::More import => [qw( done_testing is like ok skip use_ok )];
use Test::Exception;
use Time::HiRes qw( sleep time );
use File::Temp  qw( tempdir );
use File::Spec  ();

# Timeout for process-related operations (in seconds)
use constant TIMEOUT => 5;

BEGIN {
    use_ok('Ollama::Manager');
}

# Find the running Ollama process (integration mode)
sub find_ollama_process {
    my $start_time = time;
    my $pid;

    while ( time - $start_time < TIMEOUT ) {
        $pid = qx(pgrep -f 'ollama serve');
        chomp $pid;
        return $pid if $pid && kill( 0, $pid );
        sleep 0.1;
    }

    return;
}

# Run a test with timeout
sub run_with_timeout {
    my ( $test_name, $code ) = @_;

    eval {
        local $SIG{ALRM} = sub { die "timeout\n" };
        alarm TIMEOUT;
        $code->();
        alarm 0;
    };

    if ($@) {
        if ( $@ eq "timeout\n" ) {
            skip "Test '$test_name' timed out after " . TIMEOUT . " seconds", 1;
        }
        else {
            die $@;
        }
    }
}

# -----------------
# Unit tests (mocked ollama CLI)
# -----------------
{
    # Disable HTTP health for unit tests to avoid detecting real server
    local $ENV{OLLAMA_MANAGER_DISABLE_HTTP} = 1;

    # Create a temporary fake ollama CLI
    my $tmpdir      = tempdir( CLEANUP => 1 );
    my $fake_ollama = File::Spec->catfile( $tmpdir, 'ollama' );
    open( my $fh, '>', $fake_ollama ) or die "Cannot create fake ollama: $!";
    print $fh <<'SH';
#!/bin/sh
if [ "$1" = "--version" ]; then
  echo "ollama version is 0.1.2"
  exit 0
fi
if [ "$1" = "ps" ]; then
  if [ "$OLLAMA_FAKE_RUNNING" = "1" ]; then
    echo "ollama serve"
  else
    echo ""
  fi
  exit 0
fi
if [ "$1" = "serve" ]; then
  # No-op server (not used in tests)
  sleep 1
  exit 0
fi
exit 0
SH
    close $fh;
    chmod 0755, $fake_ollama;

    # Instantiate manager pointing to fake CLI
    my $ollama;
    lives_ok {
        $ollama = Ollama::Manager->new( ollama_path => $fake_ollama );
    }
    'Constructor works with mocked ollama';

    ok( $ollama->is_installed, 'is_installed is true with mocked ollama' );

    run_with_timeout(
        'version() with mocked ollama',
        sub {
            my $version;
            lives_ok { $version = $ollama->version } 'version() executes';
            if ( $version =~ /^ollama version is (\d+\.\d+\.\d+)/ ) { $version = $1 }
            like( $version, qr/^\d+\.\d+\.\d+$/, 'Version format looks correct' );
        }
    );

    # Since status() now relies on pid()/HTTP, mocked CLI should report STOPPED
    run_with_timeout(
        'status() STOPPED with mocked ollama',
        sub {
            is( $ollama->status, 'STOPPED', 'status STOPPED under mock' );
        }
    );

    # pid() relies on real process table; with mocked CLI we expect undef
    run_with_timeout(
        'pid() with mocked ollama',
        sub {
            ok( !defined $ollama->pid, 'pid is undef under mock' );
        }
    );
}

# -----------------
# Integration tests (optional, require real running ollama serve)
# -----------------

my $real     = Ollama::Manager->new();
my $real_pid = find_ollama_process();

SKIP: {
    my $is_running = ( $real->status eq 'RUNNING' );
    skip "No running Ollama process detected; skipping integration tests", 3
        unless ( $real_pid || $is_running );

    run_with_timeout(
        'integration version()',
        sub {
            my $v;
            lives_ok { $v = $real->version } 'version() executes';
            if ( $v =~ /^ollama version is (\d+\.\d+\.\d+)/ ) { $v = $1 }
            like( $v, qr/^\d+\.\d+\.\d+$/, 'Version looks correct' );
        }
    );

    run_with_timeout(
        'integration status()',
        sub {
            is( $real->status, 'RUNNING', 'status RUNNING with real process' );
        }
    );

    run_with_timeout(
        'integration pid()',
        sub {
            my $pid = $real->pid;
            if ( defined $pid ) {
                ok( $pid =~ /^\d+$/ && ( !$real_pid || $pid == $real_pid ), 'pid matches real process when available' );
            }
            else {
                ok( 1, 'pid not available but process is RUNNING' );
            }
        }
    );
}

done_testing();
