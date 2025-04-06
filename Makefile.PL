use 5.032000;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME              => 'Ollama::Manager',
    VERSION_FROM      => 'lib/Ollama/Manager.pm',
    PREREQ_PM         => {
        'File::Spec'    => 0,
        'File::Which'   => 0,
        'POSIX'         => 0,
        'Carp'          => 0,
        'Scalar::Util'  => 0,
        'Cwd'           => 0,
        'HTTP::Tiny'    => 0,
        'File::Temp'    => 0,
        'IPC::Run'      => 0,
    },
    ABSTRACT_FROM     => 'lib/Ollama/Manager.pm',
    AUTHOR            => 'Your Name <your.email@example.com>',
    LICENSE           => 'perl',
    MIN_PERL_VERSION  => '5.032000',
); 