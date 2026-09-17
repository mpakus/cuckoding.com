#!/bin/sh
set -eu

script_dir=${0%/*}
spike_dir=$(CDPATH= cd -- "$script_dir" && pwd)

cd "$spike_dir/control_plane"
rtk mix deps.get
rtk mix hex.audit
rtk mix format --check-formatted
rtk proxy env MIX_ENV=test CUCKODING_PORT=0 mix test --no-start
rtk proxy env MIX_ENV=prod mix compile --warnings-as-errors
rtk proxy env MIX_ENV=prod mix release --overwrite

cd "$spike_dir/shell"
rtk proxy mkdir -p release
rtk proxy rsync -a --delete ../control_plane/_build/prod/rel/cuckoding_shell_spike/ release/
rtk proxy chmod -R u+w release

cargo_bin=$(rtk proxy rustup which --toolchain 1.90.0 cargo)
toolchain_bin=${cargo_bin%/*}
tauri_cli=$(rtk proxy which cargo-tauri)
tauri_bin=${tauri_cli%/*}
rtk proxy env PATH="$toolchain_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$cargo_bin" fmt --manifest-path src-tauri/Cargo.toml -- --check
rtk proxy env PATH="$toolchain_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$cargo_bin" test --manifest-path src-tauri/Cargo.toml
rtk proxy env PATH="$toolchain_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$cargo_bin" clippy --manifest-path src-tauri/Cargo.toml -- -D warnings
rtk proxy env PATH="$toolchain_bin:$tauri_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  CARGO_BUILD_JOBS=1 CARGO_PROFILE_RELEASE_STRIP=none \
  "$tauri_cli" build --runner "$cargo_bin" --bundles app

cd "$spike_dir"
rtk proxy env -u GEM_HOME -u GEM_PATH PATH=/usr/bin:/bin:/usr/sbin:/sbin /usr/bin/ruby verify.rb
