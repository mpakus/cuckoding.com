#!/bin/sh
set -eu

script_dir=${0%/*}
desktop_dir=$(CDPATH= cd -- "$script_dir" && pwd)
root_dir=$(CDPATH= cd -- "$desktop_dir/.." && pwd)

cd "$root_dir"
rtk mix deps.get
rtk proxy env MIX_ENV=prod mix assets.deploy
rtk proxy env MIX_ENV=prod mix compile --warnings-as-errors
rtk proxy env MIX_ENV=prod mix release --overwrite

cd "$desktop_dir"
rtk proxy env -u GEM_HOME -u GEM_PATH PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  /usr/bin/ruby release_metadata_test.rb
rtk proxy mkdir -p release
rtk proxy rsync -a --delete "$root_dir/_build/prod/rel/cuckoding/" release/
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

rtk proxy env -u GEM_HOME -u GEM_PATH PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  /usr/bin/ruby verify.rb
