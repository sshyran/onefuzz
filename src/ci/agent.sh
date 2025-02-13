#!/bin/bash
#
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.

set -ex

exists() {
    [ -e "$1" ]
}

# only set RUSTC_WRAPPER if sccache exists
if sccache --help; then
    export RUSTC_WRAPPER=$(which sccache)
fi

# only set CARGO_INCREMENTAL on non-release builds
#
# This speeds up build time, but makes the resulting binaries slightly slower.
# https://doc.rust-lang.org/cargo/reference/profiles.html?highlight=incremental#incremental
if [ "${GITHUB_REF}" != "" ]; then
    TAG_VERSION=${GITHUB_REF#refs/tags/}
    if [ ${TAG_VERSION} == ${GITHUB_REF} ]; then
        export CARGO_INCREMENTAL=1
    fi
fi

mkdir -p artifacts/agent

cd src/agent
cargo fmt -- --check
# RUSTSEC-2020-0016: a dependency net2 (pulled in from tokio) is deprecated
# RUSTSEC-2020-0036: a dependency failure (pulled from proc-maps) is deprecated
# RUSTSEC-2019-0036: a dependency failure (pulled from proc-maps) has type confusion vulnerability
cargo audit --deny warnings --deny unmaintained --deny unsound --deny yanked --ignore RUSTSEC-2020-0016 --ignore RUSTSEC-2020-0036 --ignore RUSTSEC-2019-0036
cargo-license -j > data/licenses.json
cargo build --release --locked
cargo clippy --release -- -D warnings
# export RUST_LOG=trace
export RUST_BACKTRACE=full
cargo test --release --manifest-path ./onefuzz-supervisor/Cargo.toml

# TODO: re-enable integration tests.
# cargo test --release --manifest-path ./onefuzz-agent/Cargo.toml --features integration_test -- --nocapture
cargo test --release --manifest-path ./onefuzz-agent/Cargo.toml

cargo test --release --manifest-path ./onefuzz/Cargo.toml

cp target/release/onefuzz-agent* ../../artifacts/agent
cp target/release/onefuzz-supervisor* ../../artifacts/agent

if exists target/release/*.pdb; then
    for file in target/release/*.pdb; do
        cp ${file} ../../artifacts/agent
    done
fi
