#!/usr/bin/env bash
# Install the formula of this checkout's HEAD commit from source, start it
# with brew services, and check the office the way a member would get it.
# Runs on a GitHub macOS runner. CHECK_STATUS=0 skips the version and update
# guide checks (for a release from before the office knew about Homebrew).
set -euo pipefail

tap_dir=$(pwd)
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1
log="$(brew --prefix)/var/log/isomux.log"

brew tap isomux/isomux "$tap_dir"
brew install --build-from-source isomux/isomux/isomux
brew test isomux/isomux/isomux

version=$(brew list --versions isomux | awk '{print $2}')
tag="v$version"
libexec="$(brew --cellar isomux)/$version/libexec"
app="$libexec/isomux"

echo "::group::Agent CLIs in the keg"
arch=arm64
if [ "$(uname -m)" = "x86_64" ]; then arch=x64; fi
"$app/node_modules/@anthropic-ai/claude-agent-sdk-darwin-$arch/claude" --version
"$libexec/bin/bun" "$app/node_modules/@openai/codex/bin/codex.js" --version
echo "::endgroup::"

files_before="$RUNNER_TEMP/files-before.txt"
files_after="$RUNNER_TEMP/files-after.txt"
(cd "$libexec" && find . | sort) > "$files_before"

brew services start isomux
status=000
for _ in $(seq 1 90); do
  status=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:4000/ || true)
  [ "$status" = "200" ] && break
  sleep 2
done
echo "::group::Office log"
cat "$log" || true
echo "::endgroup::"
if [ "$status" != "200" ]; then
  echo "The office did not answer HTTP 200 (last status $status)."
  exit 1
fi
mode=$(stat -f %Lp "$log")
if [ "$mode" != "600" ]; then
  echo "The office log has mode $mode, not 600; it holds the setup key."
  exit 1
fi
if grep -q "could not read PATH from the login shell" "$log"; then
  echo "The launcher fell back to the service PATH."
  exit 1
fi

# Claim the office with its setup key, then read the update status.
jar="$RUNNER_TEMP/cookies"
key=$(<"$HOME/.isomux/setup-key")
code=$(printf '%s' "$key" | curl -s -o /dev/null -w '%{http_code}' -c "$jar" \
  -H "Origin: http://localhost:4000" \
  --data-urlencode "name=CI" \
  --data-urlencode "key@-" \
  http://localhost:4000/auth/claim)
if [ "$code" != "302" ]; then
  echo "The owner claim was refused (HTTP $code)."
  exit 1
fi
update="$RUNNER_TEMP/update.json"
curl -sf -b "$jar" http://localhost:4000/api/office/update > "$update"
echo "Update status:"
cat "$update"
echo

brew services stop isomux
(cd "$libexec" && find . | sort) > "$files_after"
if ! diff "$files_before" "$files_after"; then
  echo "The office changed files in its keg."
  exit 1
fi

if [ "${CHECK_STATUS:-1}" = "1" ]; then
  python3 -I - "$update" "$tag" <<'PY'
import json, sys
status = json.load(open(sys.argv[1]))["status"]
tag = sys.argv[2]
problems = []
if status.get("mode") != "release":
    problems.append(f"mode is {status.get('mode')!r}, not 'release'")
if (status.get("current") or {}).get("release") != tag:
    problems.append(f"the office reports {status.get('current')!r}, not {tag}")
if status.get("apply") != {"kind": "image", "guide": "homebrew"}:
    problems.append(f"apply is {status.get('apply')!r}, not the homebrew guide")
if problems:
    sys.exit("\n".join(problems))
print(f"The office reports {tag} and the homebrew update guide.")
PY
fi
