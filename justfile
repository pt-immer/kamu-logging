# kamu-logging dev tasks. Run `just` (no args) to list. Run `just gate-all`
# locally to mirror the PR gate.

# Non-wasm feature bundle. `--all-features` clashes with the
# systemd <-> wasm32 compile_error invariant; CI uses this exact string.
ci_features := "systemd,with-actix-web,with-otlp"
msrv := "1.85"

# Show the task list.
default:
    @just --list --unsorted

# --- Setup ----------------------------------------------------------------

# Install every dev tool `just gate-slow` expects.
setup:
    cargo install cargo-audit cargo-llvm-cov cargo-semver-checks
    rustup component add llvm-tools-preview
    rustup toolchain install {{msrv}}
    @echo "Optional: install cargo-deny if you maintain a deny.toml."

# Diagnose which dev tools are present on this machine.
doctor:
    @echo "=== Toolchain ==="
    @command -v cargo >/dev/null && echo "[ok]      cargo ($(cargo --version | cut -d' ' -f2))" || echo "[missing] cargo"
    @rustup toolchain list 2>/dev/null | grep -q '^{{msrv}}' && echo "[ok]      rust {{msrv}} (MSRV)" || echo "[missing] rust {{msrv}}    (run: just setup)"
    @rustup component list --installed 2>/dev/null | grep -q llvm-tools-preview && echo "[ok]      llvm-tools-preview" || echo "[missing] llvm-tools-preview (run: just setup)"
    @echo
    @echo "=== Cargo extensions ==="
    @command -v cargo-audit >/dev/null && echo "[ok]      cargo-audit" || echo "[missing] cargo-audit         (run: just setup)"
    @command -v cargo-llvm-cov >/dev/null && echo "[ok]      cargo-llvm-cov" || echo "[missing] cargo-llvm-cov      (run: just setup)"
    @command -v cargo-semver-checks >/dev/null && echo "[ok]      cargo-semver-checks" || echo "[missing] cargo-semver-checks (run: just setup)"
    @command -v cargo-deny >/dev/null && echo "[ok]      cargo-deny" || echo "[note]    cargo-deny          (optional)"
    @echo
    @echo "=== External ==="
    @command -v just >/dev/null && echo "[ok]      just" || echo "[missing] just"
    @command -v npx >/dev/null && echo "[ok]      npx (markdownlint runner)" || echo "[missing] npx (Node.js needed for lint-md)"

# --- Build ----------------------------------------------------------------

# Build with default features.
build:
    cargo build

# Build with the full non-wasm feature bundle.
build-all:
    cargo build --features {{ci_features}}

# Build for wasm32 target.
build-wasm:
    cargo build --no-default-features --features wasm32 --target wasm32-unknown-unknown

# Build every supported profile (default + systemd-only + wasm32 + with-otlp).
build-matrix: build
    cargo build --no-default-features --features systemd
    just build-wasm
    cargo build --features with-otlp

# --- Test -----------------------------------------------------------------

# Run tests with default features.
test:
    cargo test

# Run tests with the full non-wasm feature bundle.
test-all:
    cargo test --features {{ci_features}}

# Run tests with systemd only (no actix-web, no otlp).
test-systemd:
    cargo test --no-default-features --features systemd

# --- Format ---------------------------------------------------------------

# Apply rustfmt across the tree.
fmt-all:
    cargo fmt --all

# Verify rustfmt cleanliness (PR gate).
fmt-check:
    cargo fmt --all --check

# Apply markdownlint auto-fix where possible.
fmt-md:
    npx --yes markdownlint-cli2 --fix

# --- Lint -----------------------------------------------------------------

# Run every linter (Rust + Markdown).
lint-all: lint-rs lint-md

# Clippy across the full bundle + wasm32 with -D warnings.
lint-rs:
    cargo clippy --all-targets --features {{ci_features}} -- -D warnings
    cargo clippy --no-default-features --features wasm32 --target wasm32-unknown-unknown -- -D warnings

# Run markdownlint (requires Node.js / npx).
lint-md:
    npx --yes markdownlint-cli2

# Validate GitHub Actions workflow files (requires `actionlint` on PATH).
lint-actions:
    actionlint .github/workflows/*.yml

# --- Docs -----------------------------------------------------------------

# Build docs locally and open in browser.
doc-open:
    cargo doc --no-deps --features {{ci_features}} --open

# Build docs treating warnings as errors (PR gate).
doc-check:
    RUSTDOCFLAGS="-D warnings" cargo doc --no-deps --features {{ci_features}}

# --- MSRV -----------------------------------------------------------------

# Check the crate compiles on the declared MSRV (requires `rustup toolchain install {{msrv}}`).
msrv:
    rustup run {{msrv}} cargo check
    rustup run {{msrv}} cargo check --features {{ci_features}}

# --- Security -------------------------------------------------------------

# Run cargo audit with warnings promoted to errors. This catches both
# vulnerabilities (e.g. RUSTSEC time DoS) and yanked / unmaintained crates.
audit:
    cargo audit --deny warnings

# Run cargo deny check (requires `cargo install cargo-deny` and deny.toml).
deny:
    cargo deny check

# --- Coverage -------------------------------------------------------------

# Print a coverage summary (requires cargo-llvm-cov + llvm-tools-preview component).
coverage:
    cargo llvm-cov --features {{ci_features}} --summary-only

# Generate an HTML coverage report and open it.
coverage-html:
    cargo llvm-cov --features {{ci_features}} --html --open

# Generate lcov for upload to Codecov.
coverage-lcov:
    cargo llvm-cov --features {{ci_features}} --lcov --output-path lcov.info

# Run the test suite once under llvm-cov and emit both lcov + a summary
# (used by the CI coverage job to avoid running tests twice).
coverage-ci:
    cargo llvm-cov --features {{ci_features}} --no-report
    cargo llvm-cov report --lcov --output-path lcov.info
    cargo llvm-cov report --summary-only | tee coverage-summary.txt

# --- Semver --------------------------------------------------------------

# Compare current API against the published crates.io version (requires cargo-semver-checks).
semver:
    cargo semver-checks --only-explicit-features --features {{ci_features}}

# --- Examples ------------------------------------------------------------

# Run an example by name. Usage: `just example minimal` or `just example actix`.
example NAME *ARGS:
    cargo run --example {{NAME}} --features {{ci_features}} {{ARGS}}

# --- Release ------------------------------------------------------------

# Dry-run cargo publish (validates manifest + builds the package).
publish-dry:
    cargo publish --dry-run --allow-dirty

# Tag a release after verifying Cargo.toml matches. Usage: `just tag 1.0.1`.
tag VERSION:
    @grep -q '^version = "{{VERSION}}"' Cargo.toml || (echo "Update Cargo.toml version to {{VERSION}} first" >&2 && exit 1)
    git tag v{{VERSION}}
    @echo "Tagged v{{VERSION}}. Push with: git push origin v{{VERSION}}"

# --- Aggregates ---------------------------------------------------------

# Run every check that the PR gate runs. Mirrors pr.yml.
gate-all: fmt-check lint-all test-all build-wasm doc-check audit
    @echo "All PR gates passed locally."

# Like gate-all, plus the slow checks (coverage + semver + msrv).
gate-slow: gate-all coverage semver msrv
    @echo "All PR + slow gates passed locally."
