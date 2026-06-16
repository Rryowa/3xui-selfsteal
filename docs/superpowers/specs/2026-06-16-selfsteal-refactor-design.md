# Selfsteal Modular Refactor Design

## Goal
Refactor the massive `selfsteal.sh` script into a modular, maintainable structure with a Makefile-based orchestration, while retaining the ability to bundle everything back into a single `dist/selfsteal.sh` script for end-users to install via `curl | bash`.

## Architecture & Directory Structure
The repository will be restructured to isolate source code modules from the bundled distributable output.

```text
├── Makefile
├── build.sh                  # The bundler script
├── src/
│   ├── common/               # Shared utilities
│   │   ├── colors.sh
│   │   ├── logging.sh
│   │   ├── system_checks.sh
│   │   └── firewall.sh
│   └── selfsteal/            # selfsteal specific modules
│       ├── main.sh           # Entrypoint and CLI arguments parser
│       ├── acme.sh           # SSL certificate logic
│       ├── docker.sh         # Docker Hub/Image fallbacks and container logic
│       ├── templates.sh      # Template mutator and registry logic
│       └── xray_socket.sh    # The 3x-ui /dev/shm integration logic
└── dist/                     # (Ignored in git) The final bundled outputs
```

## The Bundling Mechanism
A lightweight script named `build.sh` will act as a bundler. 
- It will parse a designated entrypoint file (e.g., `src/selfsteal/main.sh`).
- Whenever it encounters a source directive (e.g., `source src/common/logging.sh`), it will inline the contents of that file in place of the `source` line.
- This produces a single, standalone bash script in the `dist/` directory, allowing developers to work modularly while releasing a single script.

## Makefile Orchestration
The project will use a `Makefile` to define developer workflows:
- `build`: Runs `build.sh` to compile `src/selfsteal/main.sh` into `dist/selfsteal.sh`.
- `run`: Builds the script and executes `dist/selfsteal.sh` locally for rapid testing.
- `clean`: Removes the `dist/` directory.

## Testing and Verification
The refactored script (`dist/selfsteal.sh`) must behave exactly identically to the original script. All existing flags (`--nginx`, `--tcp`, `@ install`), environment checks, logging outputs, template mutators, ACME certificate provisions, and socket logic must work perfectly in the bundled output.
