# Ollama::Manager

A Perl module for managing the Ollama application lifecycle, including installation, updates, and controlling the server process.

## Installation

```bash
# Install dependencies
cpanm --installdeps .

# Build and install
perl Makefile.PL
make
make test
make install
```

## Dependencies

- Perl 5.32.0 or later
- Core Perl modules:
  - File::Spec
  - File::Which
  - POSIX
  - Carp
  - Scalar::Util
  - Cwd
  - HTTP::Tiny
  - File::Temp
- Non-core Perl module:
  - IPC::Run

## Usage

```perl
use Ollama::Manager;

# Create a new manager instance
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
```

## Methods

### new(%args)

Constructor. Accepts the following optional arguments:

- `ollama_path`: Explicit path to the ollama executable
- `install_url`: URL for the Ollama installation script
- `pid_file`: Path to store the PID file

### is_installed()

Returns true if Ollama is installed and accessible.

### version()

Returns the installed Ollama version.

### install(%args)

Installs Ollama. Accepts:

- `force`: Force reinstallation even if already installed

### start(%args)

Starts the Ollama server process.

### stop(%args)

Stops the Ollama server process. Accepts:

- `timeout`: Seconds to wait for graceful shutdown before force killing

### restart(%args)

Restarts the Ollama server process.

### status()

Returns the server status: 'RUNNING', 'STOPPED', or 'UNKNOWN'.

### pid()

Returns the PID of the running Ollama server process, or undef if not running.

## License

This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

## Author

Paul Derscheid <me@paulderscheid.xyz>

## Disclosure

This library was basically one shot by Cursor with my guidance while using auto selection of models.
Keep that in mind. For more details check [DESIGN.md](DESIGN.md).