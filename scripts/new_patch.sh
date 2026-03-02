#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATCH_DIR="$ROOT_DIR/patches"

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <number> <slug>"
  echo "Example: $0 0002 load-antidetect-config-at-startup"
  exit 1
fi

number="$1"
slug="$2"
filename="${number}-${slug}.patch"
path="$PATCH_DIR/$filename"

if [[ -e "$path" ]]; then
  echo "Patch already exists: $path"
  exit 2
fi

date_rfc2822="$(LC_ALL=C date -R)"
subject_slug="${slug//-/ }"

cat >"$path" <<EOF
From 0000000000000000000000000000000000000000 Mon Sep 17 00:00:00 2001
From: anti-det <anti-det@local>
Date: ${date_rfc2822}
Subject: [PATCH] TODO: ${subject_slug}

Describe what this patch changes and why.
---
TODO_FILE | 0
1 file changed, 0 insertions(+), 0 deletions(-)

diff --git a/TODO_FILE b/TODO_FILE
new file mode 100644
index 000000000000..000000000000
--- /dev/null
+++ b/TODO_FILE
@@ -0,0 +0,0 @@
+
--
2.49.0
EOF

echo "Created patch template: $path"

