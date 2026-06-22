# Makefile Integration Design

This design documents the transition of the project's primary installation interface to a modular `Makefile` wrapping the compiled script assets in the `src/dest/` directory.

## Compilation Strategy

Instead of keeping final shell scripts in the root directory, we will compile them using `src/build.sh` and place them in the `src/dest/` directory:

- **Source Code Locations**:
  - `src/selfsteal/main.sh` (along with its modular imports under `src/selfsteal/` and `src/common/`)
  - `src/3x-ui-docker/main.sh` (source for the 3x-ui panel installer, moved from the root)
- **Compilation Output (`src/dest/`)**:
  - `src/dest/selfsteal.sh`
  - `src/dest/3x-ui-docker.sh`

## Proposed Makefile Targets

We will define/update the following targets in the `Makefile`:

- `build`: Compiles both entrypoints into `src/dest/` (`src/dest/3x-ui-docker.sh` and `src/dest/selfsteal.sh`).
- `install-sysprep`: Invokes the system tuning and BBR configuration script (`sysprep.sh`).
- `install-3x-ui`: Ensures the build is up to date, then runs `src/dest/3x-ui-docker.sh $(ARGS)`.
- `install-selfsteal`: Ensures the build is up to date, then runs `src/dest/selfsteal.sh install $(ARGS)`.
- `install-netbird`: Invokes the NetBird configuration script (`netbird.sh`) with the `menu` parameter.
- `install-all`: Sequentially runs `install-sysprep`, `install-3x-ui`, and `install-selfsteal` to perform a full system deployment.
- `clean`: Removes generated scripts inside `src/dest/` and the root folder.

All targets will support passing arbitrary flags/arguments using the `ARGS` variable, e.g., `make install-selfsteal ARGS="--domain test.com"`.

## Affected Files

- `Makefile`: Setup clean build paths for `src/dest/`.
- `src/3x-ui-docker/main.sh`: Moved from root (`3x-ui-docker.sh`).
- `README.md` & `GEMINI.md`: Update commands and descriptions to prioritize `make` over direct script execution, using compiled `src/dest/` assets.
