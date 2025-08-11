# Ollama::Manager

A Perl module and CLI for managing the Ollama application lifecycle, including installation, updates, process health, and service management.

## Installation

```bash
# Install dependencies
cpanm --installdeps .

# Build and test
perl Makefile.PL
make
make test

# Install (optional)
make install
```

## Dependencies

- Perl 5.32.0 or later
- Runtime modules:
  - File::Which, POSIX, Carp, Cwd, HTTP::Tiny, File::Temp
  - Const::Fast
  - Proc::ProcessTable (optional, for PID enumeration)
  - System::Command, IO::Select (process execution with streaming and timeouts)
- Test modules:
  - Test::More, Test::Exception, Time::HiRes, File::Temp

## Library usage

```perl
use Ollama::Manager;

# Create a new manager instance
my $ollama = Ollama::Manager->new();

# Install Ollama if not present
$ollama->install() unless $ollama->is_installed;

# Start the server (falls back to spawning the daemon)
$ollama->start();

# Check status (HTTP health first, then PID checks)
if ($ollama->status eq 'RUNNING') {
  print "Ollama is running (PID: " . ($ollama->pid // 'unknown') . ")\n";
}

# Stop the server
$ollama->stop();
```

### Integrating with Ollama::Client

Pair `Ollama::Manager` with `Ollama::Client` to ensure the daemon is running before issuing API calls.

```perl
use Ollama::Manager ();
use Ollama::Client  ();

my $mgr = Ollama::Manager->new();
$mgr->start() if $mgr->status ne 'RUNNING';

my $client = Ollama::Client->new();
my $res = $client->generate(model => 'gemma3:latest', prompt => 'Say hello');
print $res->{response},"\n" if $res;
```

### Methods

- `new(%args)`
  - `ollama_path`: explicit path to the `ollama` executable
  - `install_url`: URL for the Ollama installation script
- `is_installed()` → boolean
- `version()` → string
- `install(%args)`
  - `force`: re-install even if already installed
- `start()` → boolean
- `stop(%args)` → boolean
  - `timeout`: graceful shutdown timeout seconds (default 10)
- `restart(%args)` → boolean
- `status()` → `'RUNNING' | 'STOPPED'`
- `pid()` → PID number or undef
- CLI wrappers: `create`, `show`, `run_model`, `stop_model`, `pull`, `push`, `list`, `ps`, `cp`, `rm`, `help`

## Service adapters

To integrate with init systems instead of manual process control:

- `Ollama::Service::Systemd`
  - start/stop/status/pid using `systemctl` (user or system scope)
  - constructor: `new(unit => 'ollama', scope => 'user'|'system')`
- `Ollama::Service::Launchd`
  - start/stop/status/pid using `launchctl` (gui/$UID or system domain)
  - constructor: `new(label => 'com.ollama.ollama', scope => 'gui'|'system', uid => $EUID)`
  - If `label` is omitted, auto-detects labels containing `ollama` and prefers active ones and known patterns.

These are intended to be injected into higher-level tools (the CLI does this for you).

## CLI

The `bin/ollama-manager-cli` tool wraps the library and optionally the service adapters.

Global options:
- `--ollama-path PATH`     path to `ollama`
- `--no-http-health`       disable HTTP health checks in status detection
- `--service NAME`         `auto` (default), `launchd`, `systemd`, or `none`
- `--systemd-scope S`      `user` (default) or `system`
- `--systemd-unit U`       systemd unit name (default: `ollama`)
- `--launchd-scope S`      `gui` (default) or `system`
- `--launchd-label L`      launchd label (default auto-detect)

Common commands:
- `status`      → prints `RUNNING` or `STOPPED`
- `pid`         → prints PID or empty if unknown
- `version`     → prints `Ollama version: X.Y.Z`
- `is-installed`
- `start-server`, `stop-server`
- `list`, `ps`, `pull`, `push`, `show`, `run`, `stop`, `create`, `cp`, `rm`, `help`

Examples (macOS):
```bash
# Auto-detect launchd label and print PID
./bin/ollama-manager-cli --service launchd pid

# Explicitly use a specific label
label=$(launchctl list | awk '/application\.com\.electron\.ollama/ {print $3; exit}')
./bin/ollama-manager-cli --service launchd --launchd-label "$label" status
```

Examples (systemd):
```bash
# User scope
./bin/ollama-manager-cli --service systemd --systemd-scope user status

# System scope with custom unit name
./bin/ollama-manager-cli --service systemd --systemd-scope system --systemd-unit ollama status
```

## Notes

- Prefer managing the daemon via `systemd`/`launchd` when available.
- The library uses HTTP health, Proc::ProcessTable, lsof/pgrep, and system adapters to infer status and PID.
- Installation requires appropriate system permissions.

## License

This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

## Author

Paul Derscheid <me@paulderscheid.xyz>

## Disclosure

This library was co-developed with Cursor using automated assistance. For design details, see [DESIGN.md](DESIGN.md).