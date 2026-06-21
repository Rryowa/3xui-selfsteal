# Design Specification: Remove local sni-templates directory

## Goal
Remove the `sni-templates/` directory from the repository since templates are already fetched dynamically from GitHub by the `selfsteal.sh` script, making local templates redundant and bloating the repository size.

## Proposed Changes

### Deletions
* Remove the `sni-templates/` directory entirely.

### Modifications
* Update [README.md](file:///root/3xui-selfsteal/README.md) to remove `├── sni-templates/            # AI decoy web templates` from the directory structure tree.

## Verification Plan

### Manual Verification
* Build the `selfsteal.sh` script using `make build`.
* Run validation commands to ensure the build script is still intact and functional.
* Run the template download functionality to confirm it continues to retrieve templates dynamically from GitHub.
