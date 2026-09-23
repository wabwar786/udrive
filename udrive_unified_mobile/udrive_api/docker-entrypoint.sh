#!/bin/sh
#
# Prepares the uploads volume, then drops to the unprivileged user.
#
# Railway mounts a volume at /data owned by root. The API runs as `udrive`
# (uid 10001), which cannot create a directory inside it — and .NET reports that
# refusal as `UnauthorizedAccessException`, which is how a permission problem on
# a disk ended up telling every Driver their session had expired.
#
# The image cannot fix this ahead of time: anything chowned at build time is
# hidden the moment the volume is mounted over it. So ownership is set here, at
# start-up, after the mount exists — which needs root, which is why the
# container no longer starts as `udrive` directly.
#
# `exec setpriv` replaces this shell rather than spawning a child, so the API
# keeps PID 1 and still receives the signals Railway sends to stop it.

set -e

UPLOAD_ROOT="${UPLOAD_ROOT:-/data/uploads}"

if ! mkdir -p "$UPLOAD_ROOT" 2>/dev/null; then
    echo "WARNING: could not create '$UPLOAD_ROOT'. Uploads will fail." >&2
elif ! chown -R udrive:udrive "$UPLOAD_ROOT" 2>/dev/null; then
    # Not fatal on its own: some mounts are already owned correctly, and others
    # ignore chown entirely while still being writable.
    echo "NOTE: could not change ownership of '$UPLOAD_ROOT'." >&2
fi

exec setpriv --reuid=10001 --regid=10001 --clear-groups dotnet UDrive.Api.dll
