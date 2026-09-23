#!/usr/bin/env bash
#
# Parses every C# file with the real compiler and reports genuine syntax errors.
#
# Written because six deployments in a row failed on mistakes a compiler would
# have caught in seconds, and the only checks available here were counting
# braces with a regex.
#
# It cannot be a full build: NuGet is unreachable from this environment, so the
# project's packages (Npgsql, JwtBearer, Swashbuckle) cannot be restored. What
# it can do is run Roslyn with no references at all and keep the errors that
# survive that — anything about a missing type is an artefact of having no
# references, but a missing brace, a stray semicolon or a malformed expression
# is real and will fail the deploy.
#
# Not a substitute for `dotnet build`. If you have the .NET 10 SDK locally, run
# that instead; this is the check that works where a build does not.
#
# Usage, from udrive_api/:
#     bash tool/check_syntax.sh

set -uo pipefail

CSC=$(ls /usr/lib/dotnet/sdk/*/Roslyn/bincore/csc.dll 2>/dev/null | head -1)
if [ -z "$CSC" ]; then
  echo "No Roslyn compiler found. Install a .NET SDK, or run 'dotnet build'."
  exit 0
fi

# Errors that only mean "no references were supplied". Everything else is real.
IGNORED='CS0518|CS0246|CS0656|CS8137|CS1110|CS0103|CS8179|CS8795|CS0234|CS0400|CS1069'

OUTPUT=$(dotnet "$CSC" -nologo -langversion:preview -nostdlib -noconfig \
  -t:library -out:/dev/null \
  $(find . -name '*.cs' -not -path './obj/*' -not -path './bin/*') 2>&1 \
  | grep -E 'error CS' | grep -vE "error ($IGNORED)")

if [ -n "$OUTPUT" ]; then
  echo "$OUTPUT"
  echo "SYNTAX ERRORS: $(echo "$OUTPUT" | wc -l)"
  exit 1
fi

echo "SYNTAX ERRORS: 0"
