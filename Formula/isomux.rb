# The tap's bump workflow rewrites the url, the sha256 lines, COMMIT and the
# bun resource from the latest isomux release (.github/scripts/bump.py).
class Isomux < Formula
  desc "Office for AI coding agents: Claude Code, Codex and OpenCode"
  homepage "https://isomux.com"
  url "https://github.com/nmamano/isomux/archive/refs/tags/v2026.10.17.2.tar.gz"
  sha256 "c590c0d0c350a03ee3fbdda409b87f170a7d5ec632bd5d037a467daa2ad8ff91"
  license "BUSL-1.1"

  # The release tag's commit. The office reports it with the version.
  COMMIT = "4dee31c01174bdff7bfc73bd3abf38c635afd996".freeze

  depends_on :macos

  # The bun version the release pins in package.json (packageManager).
  resource "bun" do
    on_arm do
      url "https://github.com/oven-sh/bun/releases/download/bun-v1.4.2/bun-darwin-aarch64.zip"
      sha256 "90987a3a16d7db556d886ac3d551e7b6d3edf0a1cf43acaed622e8676be1d12f"
    end
    on_intel do
      url "https://github.com/oven-sh/bun/releases/download/bun-v1.4.2/bun-darwin-x64.zip"
      sha256 "80520d7e17526308c9185d261679ac6d27798d3803a0e9f7ff9121ab8affb012"
    end
  end

  # node_modules holds signed agent binaries (claude, codex) and the office
  # tree must stay as the release built it.
  skip_clean "libexec"

  def install
    resource("bun").stage { (libexec/"bin").install "bun" }
    bun = libexec/"bin/bun"
    app = libexec/"isomux"
    app.install Dir["*", ".*"].reject { |f| [".", ".."].include?(File.basename(f)) }
    cd app do
      system bun, "install", "--frozen-lockfile"
      system bun, "run", "build:ui"
      tag = "v#{version}"
      (app/"version-info.json").write({ version: tag, commit: COMMIT, release: tag }.to_json)
    end
    (bin/"isomux").write launcher
    chmod 0755, bin/"isomux"
  end

  # brew services starts the office under launchd, whose PATH lacks the user's
  # tools (gh, node, python3). The launcher takes PATH from the login shell,
  # which reads ~/.zprofile but not ~/.zshrc.
  def launcher
    <<~SH
      #!/bin/bash
      app="#{libexec}/isomux"
      fallback="#{HOMEBREW_PREFIX}/bin:#{HOMEBREW_PREFIX}/sbin:/usr/bin:/bin:/usr/sbin:/sbin"
      shell="${SHELL:-/bin/zsh}"
      out="$(mktemp -t isomux-path)" || out=""
      login_path=""
      if [ -n "$out" ]; then
        "$shell" -lc 'printf "__ISOMUX_PATH__%s__ISOMUX_PATH__" "$PATH"' </dev/null >"$out" 2>/dev/null &
        pid=$!
        ( sleep 10; kill -9 "$pid" 2>/dev/null ) >/dev/null 2>&1 &
        watchdog=$!
        wait "$pid" && login_path="$(cat "$out")"
        kill "$watchdog" 2>/dev/null
        wait "$watchdog" 2>/dev/null
        rm -f "$out"
      fi
      case "$login_path" in
        *__ISOMUX_PATH__*__ISOMUX_PATH__*)
          login_path="${login_path#*__ISOMUX_PATH__}"
          login_path="${login_path%%__ISOMUX_PATH__*}"
          ;;
        *) login_path="" ;;
      esac
      if [ -z "$login_path" ]; then
        echo "isomux: could not read PATH from the login shell $shell; using $fallback" >&2
        login_path="$fallback"
      fi
      export PATH="$login_path:#{libexec}/bin"
      cd "$app" || exit 1
      exec "#{libexec}/bin/bun" run server/isomux-office.ts "$@"
    SH
  end

  service do
    run opt_bin/"isomux"
    keep_alive true
    log_path var/"log/isomux.log"
    error_log_path var/"log/isomux.log"
  end

  def caveats
    <<~EOS
      Start the office now and at every login:
        brew services start isomux
      The setup link is in #{var}/log/isomux.log.
      To update: brew upgrade isomux, then brew services restart isomux.
    EOS
  end

  test do
    assert_equal "v#{version}", JSON.parse((libexec/"isomux/version-info.json").read)["release"]
    system libexec/"bin/bun", "--version"
  end
end
