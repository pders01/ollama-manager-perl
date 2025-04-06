# Plan: Perl Module - Ollama::Manager

## 1. Overview

**Goal:** Create a Perl library (`Ollama::Manager`) to manage the Ollama application lifecycle on the local machine, including installation, updates, and controlling the server process (start, stop, status check, etc.).

**Scope:**
*   **Installation/Updates:** Manage the presence and version of the `ollama` executable itself, primarily targeting the standard Linux/macOS installation method.
*   **Process Management:** Control the `ollama serve` process lifecycle.
*   **Exclusions:** This module will **not** interact with the Ollama API (e.g., sending prompts, listing models via API). Interaction for installation/management will be primarily through executing the `ollama` command-line tool or the official installation script.

**Target Audience:** Perl applications needing to programmatically install, update, and control the lifecycle of a local Ollama server instance.

**Important Considerations:**
*   **Permissions:** Installing/updating system-level software typically requires elevated privileges (root/administrator). This module will **assume** the user running the Perl script has the necessary permissions or has configured mechanisms like passwordless `sudo`. The module itself will *not* attempt to handle privilege escalation (e.g., prompting for passwords).
*   **Security:** Executing downloaded scripts (like the standard `curl | sh` method for Ollama) carries inherent security risks. Users should be aware of this when using the installation/update features.
*   **Platform:** The installation/update functionality will initially focus on the standard Linux/macOS shell script installer. Windows support for installation/update is **out of scope** for the initial version due to its different installation mechanism. Process management features (`start`, `stop`, etc.) should still aim for cross-platform compatibility where feasible.

## 2. Core Requirements

*   **Language:** Perl
*   **Compatibility:** Perl v5.32.0 or later.
*   **Dependencies:** Utilize core Perl modules **as much as possible**. Non-core modules are acceptable only if they provide substantial benefits and are widely used/trusted (e.g., `IPC::Run`).
*   **Functionality:**
    *   Detect Ollama installation.
    *   **Install** Ollama (Linux/macOS via standard install script).
    *   **Update** Ollama (Linux/macOS, likely by re-running install script or using a dedicated update command if available).
    *   Start the Ollama server process (`ollama serve`).
    *   Stop the Ollama server process.
    *   Restart the Ollama server process.
    *   Check the status (running or not) of the Ollama server process.
    *   Retrieve the Ollama version.
*   **Style:** Object-oriented interface.

## 3. Proposed Architecture

### 3.1. Main Module: `Ollama::Manager`

*   Primary namespace and class.
*   Encapsulates logic for finding, installing, updating, and interacting with the `ollama` executable and its server process.

### 3.2. Object-Oriented Approach

*   Standard Perl OO (`bless`, packages). No non-core OO frameworks.
    ```perl
    package Ollama::Manager;
    use strict;
    use warnings;

    # Core dependencies listed below

    # Official URL for the install script (may need updating)
    use constant OLLAMA_INSTALL_URL => 'https://ollama.com/install.sh';

    sub new {
        my $class = shift;
        my %args = @_;
        my $self = bless {}, $class;
        $self->_initialize(%args);
        return $self;
    }

    sub _initialize {
        my $self = shift;
        my %args = @_;
        $self->{config} = {
            ollama_path => $args{ollama_path}, # Explicit path override
            install_url => $args{install_url} || OLLAMA_INSTALL_URL,
            # Add other config like temp dirs if needed
        };
        $self->_find_ollama(); # Attempt to locate existing install
    }

    # ... other methods ...

    1;
    ```

### 3.3. Dependencies

*   **Core Modules:**
    *   `strict`, `warnings`: Essential.
    *   `File::Spec`: Platform-independent file paths.
    *   `File::Which`: Locate `ollama` executable (Core since 5.19.6).
    *   `POSIX`: Process management (`kill`, potentially `setsid`).
    *   `Carp`: Error reporting (`croak`, `confess`, `carp`).
    *   `Scalar::Util`: Utility functions.
    *   `Cwd`: Resolving paths.
    *   `HTTP::Tiny`: **Core module** for fetching the installation script (replaces need for external `curl`).
    *   `File::Temp`: For potentially saving the install script temporarily before execution.
*   **Recommended Non-Core Module:**
    *   `IPC::Run`: **Strongly recommended** for robustly running external commands (`ollama`, `sh`, potentially `ollama update`), capturing output, managing timeouts, and handling background processes. Alternatives (`system`, backticks, `IPC::Open3`) are core but significantly harder to use reliably for these tasks.

### 3.4. Configuration

*   `ollama_path`: Explicit path to `ollama` executable (optional, overrides auto-detection).
*   `install_url`: URL for the Ollama installation script (defaults to official URL, allows override).
*   Passed via `new()`.

### 3.5. Key Methods (Revised)

*   **`new(%args)`:**
    *   Constructor.
    *   Arguments: `ollama_path`, `install_url`.
    *   Action: Initializes config, calls internal `_find_ollama()` to attempt locating an existing installation.
    *   Returns: `Ollama::Manager` object.
*   **`_find_ollama()`:** (Internal helper method)
    *   Action: Uses `File::Which` (or checks explicit `ollama_path`) to find the executable. Stores path internally if found.
    *   Returns: Path string or `undef`.
*   **`is_installed()`:**
    *   Arguments: None.
    *   Action: Checks if the `ollama` executable path is known (was found by `_find_ollama`).
    *   Returns: Boolean.
*   **`version()`:**
    *   Arguments: None.
    *   Action: Runs `ollama --version` using `IPC::Run`. Parses output. Requires `is_installed` to be true.
    *   Returns: Version string or `undef`. `croak`s on execution error or if not installed.
*   **`install(%args)`:**
    *   Arguments: Optional `force` (boolean, default false).
    *   Action:
        1.  Check platform (`$^O`). `croak` if not Linux/macOS (or similar Unix).
        2.  If `is_installed()` is true and `force` is false, return true (already installed).
        3.  Warn the user about needing appropriate permissions.
        4.  Fetch the script from `install_url` using `HTTP::Tiny`. `croak` on download failure.
        5.  Execute the script: Pipe the downloaded script content to `sh` using `IPC::Run`. Example: `IPC::Run::run(['sh'], '<', \$script_content)`. Capture stdout/stderr.
        6.  Check the exit code and output of `sh` for success/failure.
        7.  After successful execution, call `_find_ollama()` again to update the internal path.
        8.  Verify installation by checking `is_installed()` again.
    *   Returns: Boolean indicating success/failure. `croak`s on critical errors (download fail, platform unsupported).
    *   **Note:** Does *not* handle `sudo` or password prompts. Assumes sufficient permissions.
*   **`update(%args)`:**
    *   Arguments: None currently envisioned, could add options later.
    *   Action:
        1.  Check platform (`$^O`). `croak` if not Linux/macOS (or similar Unix).
        2.  `croak` if `is_installed()` is false.
        3.  **Strategy 1 (Preferred if available):** Check if `ollama update` command exists and works. Execute it using `IPC::Run`. (Requires investigation into whether Ollama has this command).
        4.  **Strategy 2 (Fallback):** Re-run the installation procedure by calling `install( force => 1 )`. Clearly document that this is the fallback.
        5.  Check return status/output for success.
    *   Returns: Boolean indicating success/failure. `croak`s on critical errors.
*   **`start(%args)`:**
    *   Arguments: Optional hash for `ollama serve` environment/args.
    *   Action:
        1.  `croak` if `is_installed()` is false.
        2.  Check status. If running, return true.
        3.  Execute `ollama serve` in the background using `IPC::Run`.
        4.  Attempt to determine/store PID (check PID file, `IPC::Run` features).
        5.  Verify process started.
    *   Returns: Boolean success/failure. `croak`s on execution error.
*   **`stop(%args)`:**
    *   Arguments: Optional `timeout`.
    *   Action:
        1.  `croak` if `is_installed()` is false.
        2.  Find PID (PID file, stored PID, `ps` parsing).
        3.  Send `SIGTERM`, wait, check, optionally send `SIGKILL`.
    *   Returns: Boolean success (process stopped). `croak`s if PID not found or `kill` fails.
*   **`restart(%args)`:**
    *   Arguments: For `stop` and `start`.
    *   Action: Calls `stop()`, then `start()`.
    *   Returns: Boolean overall success.
*   **`status()`:**
    *   Arguments: None.
    *   Action:
        1.  `croak` if `is_installed()` is false.
        2.  Find PID.
        3.  Verify process existence and identity (`kill 0`, `/proc`, `ps`).
    *   Returns: Status indicator ('RUNNING', 'STOPPED', 'UNKNOWN'), PID if running, or `undef`.
*   **`pid()`:**
    *   Arguments: None.
    *   Action:
        1.  `croak` if `is_installed()` is false.
        2.  Find PID of running `ollama serve`.
    *   Returns: PID (integer) or `undef`.

### 3.6. Error Handling

*   Use `Carp::croak` for fatal errors (not installed when required, command execution fails, download fails, unsupported platform for install/update).
*   Use `Carp::carp` for warnings (already installed, `SIGKILL` used, permissions needed).
*   Return values indicate operational success/failure (boolean, status strings, PID/undef).

## 4. Implementation Notes

*   **Installation URL:** The `OLLAMA_INSTALL_URL` constant might change. Consider making it easily configurable or adding logic to find the current one if possible.
*   **Permissions:** Re-emphasize in documentation that `install`/`update` require the *user running the script* to have necessary permissions (e.g., root or passwordless `sudo` configured if the Ollama installer needs it).
*   **`ollama update` Command:** Investigate if Ollama provides a dedicated update command. Using that would be cleaner than re-running the full installer.
*   **`HTTP::Tiny`:** Use it for fetching the install script. It's core and simpler than LWP for this task. Handle potential network errors and non-200 HTTP status codes.
*   **`IPC::Run`:** Still the recommended way to run `sh`, `ollama serve`, `ollama --version`, etc. Handle timeouts, capture output, check exit codes.
*   **PID Management:** Remains a challenge. Prioritize Ollama's own PID file if it exists.
*   **Testing:** Add tests specifically for `install` and `update` (these might be harder, potentially requiring mocking `HTTP::Tiny` and `IPC::Run`, or integration tests in controlled environments like Docker). Test platform checks.

## 5. Example Usage (Conceptual - Install Flow)

```perl
use strict;
use warnings;
use Ollama::Manager;
use Try::Tiny;

my $ollama;
try {
    # Allow overriding install URL if needed
    $ollama = Ollama::Manager->new(
        # install_url => 'http://internal.mirror/ollama/install.sh'
    );
} catch {
    die "Failed to initialize Ollama Manager: $_";
};

if ( $^O !~ /^(linux|darwin|freebsd|netbsd|openbsd)$/ ) { # Basic Unix check
   print "Ollama installation/update management may not work on this OS ($^O).\n";
   # Process management might still work if ollama is manually installed
}

if ( ! $ollama->is_installed ) {
    print "Ollama not found. Attempting installation (requires permissions)...\n";
    try {
        if ( $ollama->install ) {
            print "Ollama installed successfully.\n";
            print "Version: " . ($ollama->version // 'unknown') . "\n";
        } else {
            die "Ollama installation failed. Check logs/permissions.\n";
        }
    } catch {
        die "Error during Ollama installation: $_";
    };
} else {
    print "Ollama is already installed.\n";
    print "Version: " . ($ollama->version // 'unknown') . "\n";
    # Optionally check for updates
    # print "Checking for updates...\n";
    # if ($ollama->update) { print "Update successful.\n"; }
}

# ... proceed with start/stop/status ...


