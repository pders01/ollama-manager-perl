use strict;
use warnings;
use Test::More import => [qw( done_testing is ok )];
use Test::Exception;

use lib 'lib';
use Ollama::Service::Systemd ();

{

    package DummyMgr;
    sub new { bless { calls => [] }, shift }

    sub _run_cmd {
        my ( $self, $cmd, %opts ) = @_;
        push @{ $self->{calls} }, [@$cmd];
        my $joined = join ' ', @$cmd;
        if ( $joined =~ /^systemctl --user start / ) {
            return ( 1, '', '' );
        }
        if ( $joined =~ /^systemctl --user stop / ) {
            return ( 1, '', '' );
        }
        if ( $joined =~ /^systemctl --user is-active / ) {
            my $out = $self->{state} // 'inactive';
            return ( 1, "$out\n", '' );
        }
        if ( $joined =~ /^systemctl --user show -p MainPID --value / ) {
            my $pid = defined $self->{pid} ? $self->{pid} : 0;
            return ( 1, "$pid\n", '' );
        }
        return ( 0, '', 'unknown command' );
    }
    sub calls     { shift->{calls} }
    sub set_state { $_[0]->{state} = $_[1] }
    sub set_pid   { $_[0]->{pid}   = $_[1] }
}

# User scope tests
my $mgr = DummyMgr->new;
my $svc = Ollama::Service::Systemd->new( unit => 'ollama', scope => 'user' );

lives_ok { $svc->start($mgr) } 'systemd user start ok';
lives_ok { $svc->stop($mgr) } 'systemd user stop ok';

$mgr->set_state('active');
is( $svc->status($mgr), 'RUNNING', 'status RUNNING when active' );
$mgr->set_state('inactive');
is( $svc->status($mgr), 'STOPPED', 'status STOPPED when inactive' );

$mgr->set_pid(1234);
is( $svc->pid($mgr), 1234, 'pid returns numeric PID' );
$mgr->set_pid(0);
ok( !defined $svc->pid($mgr), 'pid undef when 0' );

# System scope commands
my $mgr2 = DummyMgr->new;
my $svc2 = Ollama::Service::Systemd->new( unit => 'ollama', scope => 'system' );

# Override dummy to accept system scope
no warnings 'redefine';
*DummyMgr::_run_cmd = sub {
    my ( $self, $cmd, %opts ) = @_;
    push @{ $self->{calls} }, [@$cmd];
    my $joined = join ' ', @$cmd;
    if ( $joined =~ /^systemctl start / ) {
        return ( 1, '', '' );
    }
    if ( $joined =~ /^systemctl stop / ) {
        return ( 1, '', '' );
    }
    if ( $joined =~ /^systemctl is-active / ) {
        my $out = $self->{state} // 'inactive';
        return ( 1, "$out\n", '' );
    }
    if ( $joined =~ /^systemctl show -p MainPID --value / ) {
        my $pid = defined $self->{pid} ? $self->{pid} : 0;
        return ( 1, "$pid\n", '' );
    }
    return ( 0, '', 'unknown command' );
};
use warnings;

lives_ok { $svc2->start($mgr2) } 'systemd system start ok';
lives_ok { $svc2->stop($mgr2) } 'systemd system stop ok';

$mgr2->set_state('active');
is( $svc2->status($mgr2), 'RUNNING', 'system scope status RUNNING' );

done_testing();
