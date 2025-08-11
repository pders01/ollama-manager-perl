use strict;
use warnings;
use Test::Exception ();
use Test::More import => [qw( done_testing like skip )];
use Ollama::Manager ();

my $ollama = Ollama::Manager->new();

SKIP: {
    if ( !$ollama->is_installed ) {
        skip 'Ollama binary not installed', 1;
    }

    # CREATE (should fail gracefully if no modelfile provided)
    Test::Exception::lives_ok { $ollama->create( extra_args => ['--help'] ) } 'create() runs with --help';
    like $ollama->create( extra_args => ['--help'] ), qr/create/smxi, 'create() output contains "create"';

    # SHOW (should fail gracefully if no model provided)
    Test::Exception::lives_ok { $ollama->show( extra_args => ['--help'] ) } 'show() runs with --help';
    like $ollama->show( extra_args => ['--help'] ), qr/show/smxi, 'show() output contains "show"';

    # RUN_MODEL (should fail gracefully if no model provided)
    Test::Exception::lives_ok { $ollama->run_model( extra_args => ['--help'] ) } 'run_model() runs with --help';
    like $ollama->run_model( extra_args => ['--help'] ), qr/run/smxi, 'run_model() output contains "run"';

    # STOP_MODEL (should fail gracefully if no model provided)
    Test::Exception::lives_ok { $ollama->stop_model( extra_args => ['--help'] ) } 'stop_model() runs with --help';
    like $ollama->stop_model( extra_args => ['--help'] ), qr/stop/smxi, 'stop_model() output contains "stop"';

    # PULL (should fail gracefully if no model provided)
    Test::Exception::lives_ok { $ollama->pull( extra_args => ['--help'] ) } 'pull() runs with --help';
    like $ollama->pull( extra_args => ['--help'] ), qr/pull/smxi, 'pull() output contains "pull"';

    # PUSH (should fail gracefully if no model provided)
    Test::Exception::lives_ok { $ollama->push( extra_args => ['--help'] ) } 'push() runs with --help';
    like $ollama->push( extra_args => ['--help'] ), qr/push/smxi, 'push() output contains "push"';

    # LIST
    Test::Exception::lives_ok { $ollama->list( extra_args => ['--help'] ) } 'list() runs with --help';
    like $ollama->list( extra_args => ['--help'] ), qr/list/smxi, 'list() output contains "list"';

    # PS
    Test::Exception::lives_ok { $ollama->ps( extra_args => ['--help'] ) } 'ps() runs with --help';
    like $ollama->ps( extra_args => ['--help'] ), qr/ps|process|serve/smxi, 'ps() output contains "ps" or related keyword';

    # CP (should fail gracefully if no src/dest provided)
    Test::Exception::lives_ok { $ollama->cp( extra_args => ['--help'] ) } 'cp() runs with --help';
    like $ollama->cp( extra_args => ['--help'] ), qr/cp|copy/smxi, 'cp() output contains "cp" or "copy"';

    # RM (should fail gracefully if no model provided)
    Test::Exception::lives_ok { $ollama->rm( extra_args => ['--help'] ) } 'rm() runs with --help';
    like $ollama->rm( extra_args => ['--help'] ), qr/rm|remove/smxi, 'rm() output contains "rm" or "remove"';

    # HELP
    Test::Exception::lives_ok { $ollama->help( extra_args => ['--help'] ) } 'help() runs with --help';
    like $ollama->help( extra_args => ['--help'] ), qr/help/smxi, 'help() output contains "help"';
}

done_testing();
