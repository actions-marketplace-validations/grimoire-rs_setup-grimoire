# Shared Bats helpers for the fixture release server.
# Sourced via `load helpers/server` from individual .bats files.
#
# There are no static archives checked in. Every fixture release (archive +
# .sha256 sidecar) is built at runtime by server_build_release below, then
# served by server_start over HTTPS (python3 + ssl).
#
# The fixture server speaks HTTPS, not plain HTTP, because install.sh passes
# curl `--proto '=https'` — a plain-HTTP fixture can never be reached, and
# relaxing that flag for tests would stop testing the shipped code. A static,
# long-lived self-signed cert for 127.0.0.1 lives next to this file
# (localhost-cert.pem / localhost-combined.pem). Tests trust THAT specific cert
# via CURL_CA_BUNDLE — this establishes trust for the localhost fixture only; it
# does NOT disable TLS verification.
#
# Set GRIM_FIXTURE_HEADER_LOG before server_start to have every request's
# headers appended to that file (used to prove the auth header is sent).

# Directory containing this helper (and the vendored test cert), located from
# this file's own path so suites at any depth under tests/install/ work.
_server_helper_dir() {
    (cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
}

# Path to the CA cert tests should trust (export as CURL_CA_BUNDLE).
server_ca_bundle() {
    printf '%s/localhost-cert.pem' "$(_server_helper_dir)"
}

server_start() {
    local _root="$1" _logfile="$2"
    local _combined
    _combined="$(_server_helper_dir)/localhost-combined.pem"
    (
        cd "$_root" || {
            echo "server_start: cd '$_root' failed"
            exit 1
        }
        # Pre-exec marker: proves the logfile redirect works and records the
        # interpreter + cert state, so an empty log and a python traceback stay
        # distinguishable when this leg fails.
        echo "server_start: python3=$(command -v python3) ver=$(python3 -V 2>&1) cert=${_combined} exists=$([ -f "$_combined" ] && echo yes || echo no)"
        GRIM_FIXTURE_CERT="$_combined"
        export GRIM_FIXTURE_CERT
        exec python3 -u -c '
import http.server, ssl, os, sys, socketserver
cert = os.environ["GRIM_FIXTURE_CERT"]
header_log = os.environ.get("GRIM_FIXTURE_HEADER_LOG")

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if header_log:
            with open(header_log, "a") as fh:
                fh.write("%s %s\n%s\n" % (self.command, self.path, self.headers))
        return super().do_GET()

class _Srv(http.server.HTTPServer):
    # Skip HTTPServer.server_bind getfqdn() reverse-DNS lookup: it blocks past
    # the 10s startup timeout on macOS runners, so the server never reached the
    # port print. Bind only; no name resolution.
    def server_bind(self):
        socketserver.TCPServer.server_bind(self)
        self.server_name = self.server_address[0]
        self.server_port = self.server_address[1]

httpd = _Srv(("127.0.0.1", 0), Handler)
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(cert)
httpd.socket = ctx.wrap_socket(httpd.socket, server_side=True)
sys.stderr.write("Serving HTTPS on 127.0.0.1 port %d\n" % httpd.socket.getsockname()[1])
sys.stderr.flush()
httpd.serve_forever()
'
    ) >"$_logfile" 2>&1 <&- 3>&- &
    local _pid=$!
    local _port=""
    for _ in $(seq 1 100); do
        _port=$(grep -oE 'port [0-9]+' "$_logfile" 2>/dev/null | head -1 | awk '{print $2}')
        [ -n "$_port" ] && break
        sleep 0.1
    done
    [ -z "$_port" ] && {
        # Surface WHY the server never reported a port (python missing, cert
        # load failure, ...) instead of a bare failure out of setup().
        {
            echo "server_start: HTTPS fixture server did not report a port within 10s"
            echo "server_start: python3=$(command -v python3 || echo MISSING)"
            echo "server_start: --- server log ($_logfile) ---"
            cat "$_logfile" 2>/dev/null || echo "(no log)"
            echo "server_start: --- end server log ---"
        } >&2
        kill "$_pid" 2>/dev/null
        return 1
    }
    printf '%s %s\n' "$_pid" "$_port"
}

server_stop() {
    [ -n "${1:-}" ] && kill "$1" 2>/dev/null || true
}

# Asset stem for the host platform. Mirrors the `case` in
# .github/scripts/install.sh exactly — if that mapping changes, this must too,
# or every download test 404s instead of asserting what it means to.
server_detect_stem() {
    case "$(uname -s)/$(uname -m)" in
        Linux/x86_64) echo "grimoire-x86_64-unknown-linux-gnu" ;;
        Linux/aarch64 | Linux/arm64) echo "grimoire-aarch64-unknown-linux-gnu" ;;
        Darwin/x86_64) echo "grimoire-x86_64-apple-darwin" ;;
        Darwin/arm64) echo "grimoire-aarch64-apple-darwin" ;;
        *)
            echo "unsupported-platform"
            return 1
            ;;
    esac
}

# Portable sha256 of a file: coreutils sha256sum (Linux) or BSD/macOS shasum.
server_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

# Body of the fixture `grim` stub: enough for `grim --version` to answer, which
# is all the action's report step asks of it.
server_stub_body() {
    cat <<'STUB'
#!/bin/sh
case "$1" in
    --version | version) echo "grim 0.0.0" ;;
    *) echo "stub grim" ;;
esac
STUB
}

# Publish a file plus its .sha256 sidecar under both release layouts the action
# knows: download/<tag>/ (pinned version) and latest/download/ (the `latest`
# redirect). $4 overrides the checksum written to the sidecar — that is how the
# mismatch test lies about it.
server_publish() {
    local _srv="$1" _tag="$2" _src="$3" _sum="${4:-}" _name _dir
    _name="$(basename "$_src")"
    [ -n "$_sum" ] || _sum="$(server_sha256 "$_src")"
    for _dir in "$_srv/download/$_tag" "$_srv/latest/download"; do
        mkdir -p "$_dir"
        cp "$_src" "$_dir/$_name"
        printf '%s  %s\n' "$_sum" "$_name" >"$_dir/$_name.sha256"
    done
}

# Build a release archive containing a stub `grim` and publish it.
#
# Args: $1 server root, $2 tag, $3 extension (tar.xz|tar.gz, default tar.xz),
#       $4 extra file count — that many additional entries also named `grim`,
#          used by the SIGPIPE regression fixture.
# Echoes the archive filename.
server_build_release() {
    local _srv="$1" _tag="$2" _ext="${3:-tar.xz}" _extra="${4:-0}" _stem _file _build _i
    _stem="$(server_detect_stem)"
    _file="$_stem.$_ext"
    _build="${BATS_TEST_TMPDIR:-$BATS_FILE_TMPDIR}/build-$_tag-$_ext"
    rm -rf "$_build"
    mkdir -p "$_build/$_stem"
    server_stub_body >"$_build/$_stem/grim"
    chmod +x "$_build/$_stem/grim"

    # Additional files, all named `grim`, one per directory. `find -name grim`
    # prints every one of them, which is what floods the pipe.
    _i=0
    while [ "$_i" -lt "$_extra" ]; do
        mkdir -p "$_build/$_stem/pad/$_i"
        printf 'pad\n' >"$_build/$_stem/pad/$_i/grim"
        _i=$((_i + 1))
    done

    case "$_ext" in
        tar.xz) (cd "$_build" && tar cJf "$_file" "$_stem") ;;
        tar.gz) (cd "$_build" && tar czf "$_file" "$_stem") ;;
        *)
            echo "server_build_release: unknown extension '$_ext'" >&2
            return 1
            ;;
    esac

    server_publish "$_srv" "$_tag" "$_build/$_file"
    printf '%s\n' "$_file"
}
