#!/bin/sh
set -eu

script_dir=${0%/*}
desktop_dir=$(CDPATH= cd -- "$script_dir" && pwd)
release_dir="$desktop_dir/release"

mach_o_files=$(rtk proxy env -u GEM_HOME -u GEM_PATH PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  /usr/bin/ruby "$desktop_dir/mach_o_files.rb" "$release_dir")
crypto_source=

for binary in $mach_o_files; do
  dependencies=$(rtk proxy /usr/bin/otool -L "$binary" | rtk tail -n +2 | rtk awk '{print $1}')
  for dependency in $dependencies; do
    case "$dependency" in
      /System/*|/usr/lib/*|@*) ;;
      /*libcrypto*.dylib)
        if [ -n "$crypto_source" ] && [ "$crypto_source" != "$dependency" ]; then
          echo "multiple external libcrypto dependencies are unsupported" >&2
          exit 65
        fi
        crypto_source=$dependency
        ;;
    esac
  done
done

if [ -z "$crypto_source" ] || [ ! -f "$crypto_source" ]; then
  echo "release does not contain one resolvable external libcrypto dependency" >&2
  exit 66
fi

crypto_name=${crypto_source##*/}
crypto_dir=${release_dir}/lib/crypto-*/priv/lib
set -- $crypto_dir
if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
  echo "release must contain exactly one OTP crypto private library directory" >&2
  exit 65
fi
crypto_dir=$1
bundled_crypto="$crypto_dir/$crypto_name"

rtk proxy cp -L "$crypto_source" "$bundled_crypto"
rtk proxy chmod u+w "$bundled_crypto"
rtk proxy /usr/bin/codesign --remove-signature "$bundled_crypto" 2>/dev/null || true
rtk proxy /usr/bin/install_name_tool -id "@loader_path/$crypto_name" "$bundled_crypto"
rtk proxy /usr/bin/codesign --force --sign - "$bundled_crypto"

for binary in $mach_o_files; do
  dependencies=$(rtk proxy /usr/bin/otool -L "$binary" | rtk tail -n +2 | rtk awk '{print $1}')
  for dependency in $dependencies; do
    if [ "$dependency" = "$crypto_source" ]; then
      rtk proxy /usr/bin/codesign --remove-signature "$binary" 2>/dev/null || true
      rtk proxy /usr/bin/install_name_tool -change "$crypto_source" \
        "@loader_path/$crypto_name" "$binary"
      rtk proxy /usr/bin/codesign --force --sign - "$binary"
    fi
  done
done

mach_o_files=$(rtk proxy env -u GEM_HOME -u GEM_PATH PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  /usr/bin/ruby "$desktop_dir/mach_o_files.rb" "$release_dir")
for binary in $mach_o_files; do
  binary_id=$(rtk proxy /usr/bin/otool -D "$binary" | rtk tail -n 1)
  dependencies=$(rtk proxy /usr/bin/otool -L "$binary" | rtk tail -n +2 | rtk awk '{print $1}')
  for dependency in $dependencies; do
    [ "$dependency" = "$binary_id" ] && continue
    case "$dependency" in
      /System/*|/usr/lib/*|@*) ;;
      /*)
        echo "external native dependency remains: $binary -> $dependency" >&2
        exit 65
        ;;
    esac
  done
done

resolved_source=$(rtk proxy env -u GEM_HOME -u GEM_PATH PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  /usr/bin/ruby -e 'puts File.realpath(ARGV[0])' "$crypto_source")
case "$resolved_source" in
  */Cellar/openssl@3/*)
    version=${resolved_source#*/Cellar/openssl@3/}
    version=${version%%/*}
    ;;
  *)
    version=${crypto_name#libcrypto.}
    version=${version%.dylib}
    ;;
esac
relative_crypto=${bundled_crypto#"$release_dir"/}
rtk proxy env -u GEM_HOME -u GEM_PATH PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  /usr/bin/ruby -rjson -e \
  'puts JSON.pretty_generate({"dependencies" => [{"name" => "openssl", "version" => ARGV[0], "license" => "Apache-2.0", "path" => ARGV[1]}]})' \
  "$version" "$relative_crypto" > "$release_dir/native-dependencies.json"

echo "Bundled $crypto_name and removed host-only native library paths"
