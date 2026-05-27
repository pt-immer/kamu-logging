# kamu-logging dev tasks. Run `just` (no args) to list. Run `just verify`
# locally to mirror what the PR gate runs.

# Non-wasm feature bundle. `--all-features` clashes with the
# systemd <-> wasm32 compile_error invariant; CI uses this exact string.
ci_features := "systemd,with-actix-web,with-otlp"
msrv := "1.85"

# Show the task list.
default:
    @just --list --unsorted

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

# Build everything (default + systemd-only + wasm32 + with-otlp).
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

# --- Format ---------------------------------------------------------------

# Apply rustfmt across the tree.
fmt:
    cargo fmt --all

# Verify rustfmt cleanliness (PR gate).
fmt-check:
    cargo fmt --all --check

# --- Lint -----------------------------------------------------------------

# Clippy across the full bundle + wasm32 with -D warnings.
clippy:
    cargo clippy --all-targets --features {{ci_features}} -- -D warnings
    cargo clippy --no-default-features --features wasm32 --target wasm32-unknown-unknown -- -D warnings

# Markdown lint (requires Node.js / npx).
md-lint:
    npx --yes markdownlint-cli2

# Markdown lint with auto-fix where possible.
md-fix:
    npx --yes markdownlint-cli2 --fix

# --- Docs -----------------------------------------------------------------

# Build docs locally and open in browser.
doc:
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

# Run cargo audit (requires `cargo install cargo-audit`).
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

# Run every check that the PR gate runs, in CI order. Mirrors pr.yml.
verify: fmt-check clippy test-all build-wasm doc-check md-lint audit
    @echo "All PR gates passed locally."

# Like verify, plus the slow checks (coverage + semver + msrv).
verify-full: verify coverage semver msrv
    @echo "All PR + nightly-style gates passed locally."

# Install all the tooling `just verify-full` needs.
install-tools:
    cargo install cargo-audit cargo-llvm-cov cargo-semver-checks
    rustup component add llvm-tools-preview
    rustup toolchain install {{msrv}}
    @echo "Don't forget: deny.toml is optional; install cargo-deny if you use it."
