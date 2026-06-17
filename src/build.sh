#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# Bundler script to inline 'source' or '.' directives recursively
inline_file() {
    local file="$1"
    local dir
    dir=$(dirname "$file")
    
    # Read the file line by line
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Match lines starting with optional whitespace, followed by 'source' or '.', then whitespace, then the file path
        if [[ "$line" =~ ^[[:space:]]*(source|\.)[[:space:]]+([^[:space:]]+) ]]; then
            local src_target="${BASH_REMATCH[2]}"
            # Remove any single or double quotes around the path if present
            src_target="${src_target#\'}"
            src_target="${src_target%\'}"
            src_target="${src_target#\"}"
            src_target="${src_target%\"}"

            # Resolve path relative to project root or directory of the containing file
            local resolved_path="$src_target"
            if [[ ! -f "$resolved_path" ]]; then
                resolved_path="$dir/$src_target"
            fi
            
            if [[ -f "$resolved_path" ]]; then
                inline_file "$resolved_path"
            else
                # If we cannot resolve the file, keep the source command intact
                echo "$line"
            fi
        else
            echo "$line"
        fi
    done < "$file"
}

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <entrypoint-script>" >&2
    exit 1
fi

inline_file "$1"
