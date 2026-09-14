#!/usr/bin/env bash
# The rule from the brief, section 6: ML Kit is imported in exactly one file.
# Run in CI. Exits non-zero the moment the abstraction leaks.
set -euo pipefail
cd "$(dirname "$0")/.."

leaks=$(grep -rl "google_mlkit" lib/ --include="*.dart" | grep -v "^lib/ocr/mlkit_ocr_engine.dart$" || true)

if [ -n "$leaks" ]; then
  echo "OCR boundary leaked. ML Kit may only be imported by lib/ocr/mlkit_ocr_engine.dart:"
  echo "$leaks"
  exit 1
fi

echo "OCR boundary intact."
