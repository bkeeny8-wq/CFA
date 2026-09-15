#!/bin/sh
# Writes the worker gate token into the built Info.plist.
#
# The token used to be a literal in GraderConfig.swift. This repository is
# public, so it sat readable on GitHub for eight weeks. It now lives in
# Secrets/proxy-token.txt, which is gitignored, and is injected here.
#
# This does NOT make the token secret — it still ships inside the binary and
# `strings` will find it. What it buys is that the value is no longer published
# in source or history, and rotating it needs neither a history rewrite nor a
# public commit. The protection that matters is in the worker: spend caps and
# an instant revoke.
#
# No token file (a fresh clone, CI) is not an error: the key is written empty,
# the app builds, and essay grading reports itself unconfigured.
set -eu

PLIST="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
SRC="${SRCROOT}/Secrets/proxy-token.txt"

TOKEN=""
if [ -f "$SRC" ]; then
    TOKEN=$(tr -d '\r\n' < "$SRC")
fi

if [ ! -f "$PLIST" ]; then
    echo "warning: Info.plist not found at $PLIST; skipping token injection"
    exit 0
fi

/usr/libexec/PlistBuddy -c "Delete :GraderProxyToken" "$PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :GraderProxyToken string ${TOKEN}" "$PLIST"

if [ -z "$TOKEN" ]; then
    echo "warning: Secrets/proxy-token.txt missing - essay grading disabled in this build"
fi
