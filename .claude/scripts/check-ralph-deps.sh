#!/usr/bin/env bash
# Ralph dependency verification
# Checks for required tools (bd, git, jq) and optional tools (tldr)

set -euo pipefail

REQUIRED_DEPS=(bd git jq)
OPTIONAL_DEPS=(tldr)

check_deps() {
  local missing_required=()
  local missing_optional=()

  for dep in "${REQUIRED_DEPS[@]}"; do
    if ! command -v "$dep" &> /dev/null; then
      missing_required+=("$dep")
    fi
  done

  for dep in "${OPTIONAL_DEPS[@]}"; do
    if ! command -v "$dep" &> /dev/null; then
      missing_optional+=("$dep")
    fi
  done

  if [ ${#missing_required[@]} -gt 0 ]; then
    echo "ERROR: Missing required dependencies: ${missing_required[*]}"
    exit 1
  fi

  if [ ${#missing_optional[@]} -gt 0 ]; then
    echo "WARNING: Missing optional dependencies: ${missing_optional[*]} - degraded mode"
  fi

  echo "All required dependencies available"
}

check_deps
