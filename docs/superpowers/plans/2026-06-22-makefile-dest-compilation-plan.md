# Makefile Dest Compilation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Compile both 3x-ui docker setup and selfsteal into two shell scripts inside the `src/dest/` directory, and automate their builds/execution via updated Makefile targets.

**Architecture:** Move the root-level `3x-ui-docker.sh` into `src/3x-ui-docker/main.sh`, run `src/build.sh` on both main entry points to output them to `src/dest/`, configure targets in the `Makefile` to run the compiled binaries, and update README and GEMINI onboarding docs.

**Tech Stack:** Bash, GNU Make, Docker

---

### Task 1: Move 3x-ui Docker Panel Script to Source
**Files:**
- Create: `src/3x-ui-docker/main.sh`
- Delete: `3x-ui-docker.sh`

- [ ] **Step 1: Create the directory `src/3x-ui-docker` if it does not exist.**
- [ ] **Step 2: Move `3x-ui-docker.sh` into `src/3x-ui-docker/main.sh`.**
- [ ] **Step 3: Remove the old `3x-ui-docker.sh` from the root directory.**
- [ ] **Step 4: Commit changes.**
  ```bash
  git add src/3x-ui-docker/main.sh
  git rm 3x-ui-docker.sh
  git commit -m "refactor: move 3x-ui-docker.sh to src/3x-ui-docker/main.sh"
  ```

---

### Task 2: Update Makefile Targets
**Files:**
- Modify: `Makefile`

- [ ] **Step 1: Update `Makefile` to create `src/dest/` directory and compile both `3x-ui-docker.sh` and `selfsteal.sh` into it.**
  ```makefile
  .PHONY: build run clean install-sysprep install-3x-ui install-selfsteal install-netbird install-all

  build: src/dest/selfsteal.sh src/dest/3x-ui-docker.sh

  src/dest/selfsteal.sh: src/selfsteal/main.sh src/build.sh $(shell find src/selfsteal src/common -type f -name '*.sh')
  	@mkdir -p src/dest
  	@echo "Building src/dest/selfsteal.sh..."
  	@bash src/build.sh src/selfsteal/main.sh > src/dest/selfsteal.sh
  	@chmod +x src/dest/selfsteal.sh

  src/dest/3x-ui-docker.sh: src/3x-ui-docker/main.sh src/build.sh
  	@mkdir -p src/dest
  	@echo "Building src/dest/3x-ui-docker.sh..."
  	@bash src/build.sh src/3x-ui-docker/main.sh > src/dest/3x-ui-docker.sh
  	@chmod +x src/dest/3x-ui-docker.sh

  run: build
  	@./src/dest/selfsteal.sh $(ARGS)

  clean:
  	@rm -rf src/dest

  install-sysprep:
  	@bash ./sysprep.sh

  install-3x-ui: build
  	@./src/dest/3x-ui-docker.sh $(ARGS)

  install-selfsteal: build
  	@./src/dest/selfsteal.sh install $(ARGS)

  install-netbird:
  	@bash ./netbird.sh menu

  install-all: install-sysprep install-3x-ui install-selfsteal
  ```
- [ ] **Step 2: Test Makefile syntax by running `make clean` then `make build`.**
  Expected output:
  ```
  Building src/dest/selfsteal.sh...
  Building src/dest/3x-ui-docker.sh...
  ```
- [ ] **Step 3: Commit Makefile changes.**
  ```bash
  git add Makefile
  git commit -m "build: compile 3x-ui and selfsteal scripts to src/dest/"
  ```

---

### Task 3: Update Onboarding Documentation
**Files:**
- Modify: `README.md`
- Modify: `GEMINI.md`

- [ ] **Step 1: Replace any references to direct execution of `3x-ui-docker.sh` and `selfsteal.sh` with the corresponding `make` commands.**
- [ ] **Step 2: Document the `src/dest/` build outputs and how `make build` populates them.**
- [ ] **Step 3: Commit documentation updates.**
  ```bash
  git add README.md GEMINI.md
  git commit -m "docs: update onboarding with makefile commands and src/dest outputs"
  ```

---

### Task 4: Verification and Dry Run
**Files:**
- Test: Build validation

- [ ] **Step 1: Build everything cleanly.**
  Run: `make clean && make build`
  Expected: Both scripts successfully compile inside `src/dest/`.
- [ ] **Step 2: Verify both scripts run help message.**
  Run: `./src/dest/3x-ui-docker.sh --help` or similar dry-run command.
  Expected: Script starts and prints parameter help/validation without errors.
- [ ] **Step 3: Verify selfsteal script compiles and works.**
  Run: `./src/dest/selfsteal.sh --help`
  Expected: Prints usage instructions.
- [ ] **Step 4: Save final walkthrough.**
