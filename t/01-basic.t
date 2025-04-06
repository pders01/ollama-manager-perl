use strict;
use warnings;
use Test::More;
use Test::Exception;

BEGIN {
    use_ok('Ollama::Manager');
}

my $ollama;

# Test constructor
lives_ok {
    $ollama = Ollama::Manager->new();
} 'Constructor works';

# Test is_installed
ok(defined $ollama->is_installed, 'is_installed returns a value');

# Test version if installed
SKIP: {
    skip 'Ollama not installed', 1 unless $ollama->is_installed;
    
    lives_ok {
        my $version = $ollama->version;
        # Handle both old and new version formats
        if ($version =~ /^ollama version is (\d+\.\d+\.\d+)/) {
            $version = $1;
        }
        like($version, qr/^\d+\.\d+\.\d+$/, 'Version format looks correct');
    } 'version() works';
}

# Test status
lives_ok {
    my $status = $ollama->status;
    ok($status =~ /^(RUNNING|STOPPED)$/, 'Status is valid');
} 'status() works';

# Test pid
lives_ok {
    my $pid = $ollama->pid;
    if ($ollama->status eq 'RUNNING') {
        ok($pid =~ /^\d+$/, 'PID is numeric when running');
    } else {
        ok(!defined $pid, 'PID is undef when stopped');
    }
} 'pid() works';

done_testing(); 