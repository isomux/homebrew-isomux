# The tap's bump workflow rewrites the url, the sha256 lines, COMMIT and the
# bun resource from the latest isomux release (.github/scripts/bump.py).
class Isomux < Formula
  desc "Office for AI coding agents: Claude Code, Codex and OpenCode"
  homepage "https://isomux.com"
  url "https://github.com/nmamano/isomux/archive/refs/tags/v2026.10.29.tar.gz"
  sha256 "889ac4dd41f1359b756b299d07d578b28dd1edf27acae47681f0032aee8d3c79"
  license "BUSL-1.1"

  # The release tag's commit. The office reports it with the version.
  COMMIT = "86135b150dbccc1e2eee53179caa854be7f0eb02".freeze

  depends_on :macos

  # The bun version the release pins in package.json (packageManager).
  resource "bun" do
    on_arm do
      url "https://github.com/oven-sh/bun/releases/download/bun-v1.4.4/bun-darwin-aarch64.zip"
      sha256 "c240d7f0ccb90c263a849fcdb09b7ee62630d921348ed6aafda86b9d577bc510"
    end
    on_intel do
      url "https://github.com/oven-sh/bun/releases/download/bun-v1.4.4/bun-darwin-x64.zip"
      sha256 "50a3491f73abc2fe81673171a85762d3bc2cc1680ccecadd983de99adf77977e"
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
      # The office prints its setup key to the log, which launchd has already
      # opened in a directory other accounts can read.
      umask 077
      chmod 600 "#{var}/log/isomux.log" 2>/dev/null
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
