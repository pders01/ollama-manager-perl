use 5.032000;
use ExtUtils::MakeMaker qw( WriteMakefile );

WriteMakefile(
    NAME         => 'Ollama::Manager',
    VERSION_FROM => 'lib/Ollama/Manager.pm',
    PREREQ_PM    => {
        'File::Spec'         => 0,
        'File::Which'        => 0,
        'POSIX'              => 0,
        'Carp'               => 0,
        'Cwd'                => 0,
        'HTTP::Tiny'         => 0,
        'File::Temp'         => 0,
        'Proc::ProcessTable' => 0,
        'Const::Fast'        => 0,
        'System::Command'    => 0,
        'IO::Select'         => 0,
    },
    TEST_REQUIRES => {
        'Test::More'      => 0,
        'Test::Exception' => 0,
        'Time::HiRes'     => 0,
        'File::Temp'      => 0,
        'Const::Fast'     => 0,
        'IPC::Open3'      => 0,
        'Symbol'          => 0,
        'Carp'            => 0,
    },
    ABSTRACT_FROM    => 'lib/Ollama/Manager.pm',
    AUTHOR           => 'Paul Derscheid <me@paulderscheid.xyz>',
    LICENSE          => 'perl',
    MIN_PERL_VERSION => '5.032000',
);
