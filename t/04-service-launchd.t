use strict;
use warnings;
use Test::More;
use Test::Exception;

use lib 'lib';
use Ollama::Service::Launchd;

{
    package DummyMgrL;
    sub new { bless { calls => [] }, shift }
    sub _run_cmd {
        my ($self, $cmd, %opts) = @_;
        push @{ $self->{calls} }, [ @$cmd ];
        my $joined = join ' ', @$cmd;
        if ($joined =~ /^launchctl kickstart -k /) {
            return (1, '', '');
        }
        if ($joined =~ /^launchctl stop /) {
            return (1, '', '');
        }
        if ($joined =~ /^launchctl print /) {
            my $state = $self->{state} // 'inactive';
            my $pid   = defined $self->{pid} ? $self->{pid} : 0;
            my $out = "state = $state\n";
            $out   .= "pid = $pid\n" if $state eq 'running';
            return (1, $out, '');
        }
        return (0, '', 'unknown command');
    }
    sub calls { shift->{calls} }
    sub set_state { $_[0]->{state} = $_[1] }
    sub set_pid   { $_[0]->{pid}   = $_[1] }
}

my $mgr = DummyMgrL->new;
my $svc = Ollama::Service::Launchd->new(label => 'com.ollama.ollama', scope => 'gui', uid => 501);

lives_ok { $svc->start($mgr) } 'launchd kickstart ok';
lives_ok { $svc->stop($mgr) }  'launchd stop ok';

$mgr->set_state('running');
is( $svc->status($mgr), 'RUNNING', 'status RUNNING when running' );
$mgr->set_state('inactive');
is( $svc->status($mgr), 'STOPPED', 'status STOPPED when inactive' );

$mgr->set_state('running');
$mgr->set_pid(2222);
is( $svc->pid($mgr), 2222, 'pid returns numeric PID' );
$mgr->set_state('inactive');
ok( !defined $svc->pid($mgr), 'pid undef when inactive' );

# Optional real test on macOS if OLLAMA_TEST_LAUNCHD=1
SKIP: {
    skip 'macOS launchd test skipped (set OLLAMA_TEST_LAUNCHD=1)', 2 unless $^O eq 'darwin' && $ENV{OLLAMA_TEST_LAUNCHD};
    my $real_mgr = DummyMgrL->new;
    my $real = Ollama::Service::Launchd->new(label => 'com.ollama.ollama', scope => 'gui');
    lives_ok { $real->status($real_mgr) } 'launchd status (real) lives';
    lives_ok { $real->pid($real_mgr) }    'launchd pid (real) lives';
}

done_testing();
