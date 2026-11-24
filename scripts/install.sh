#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd -P)"
tap="mic-mini/local"
formula="$tap/mic-mini"
tap_source="$project_dir/dist/homebrew-local"

export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1
tap_dir="$(brew --repo "$tap")"

version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$project_dir/app/Info.plist")"
mkdir -p "$tap_source/Formula" "$tap_source/artifacts"
if [[ ! -d "$tap_source/.git" ]]; then
    git -C "$tap_source" init --quiet --initial-branch=main --template=""
fi
staging="$(mktemp -d "$project_dir/dist/.package.XXXXXXXX")"
trap 'rm -rf "$staging"' EXIT
COPYFILE_DISABLE=1 tar -czf "$staging/MicMini.tar.gz" -C "$project_dir" Sources app scripts/build.sh
checksum="$(shasum -a 256 "$staging/MicMini.tar.gz" | cut -d ' ' -f 1)"
archive="MicMini-$checksum.tar.gz"
rm -f "$tap_source"/artifacts/MicMini-*.tar.gz
mv "$staging/MicMini.tar.gz" "$tap_source/artifacts/$archive"

cat > "$tap_source/Formula/mic-mini.rb" <<EOF
class MicMini < Formula
  desc "Microphone recorder for meetings"
  homepage "file://#{URI::DEFAULT_PARSER.escape("#{HOMEBREW_LIBRARY}/Taps/mic-mini/homebrew-local")}"
  url "#{homepage}/artifacts/$archive"
  version "$version"
  sha256 "$checksum"

  depends_on macos: :tahoe

  def install
    system "./scripts/build.sh"
    prefix.install "dist/Mic Mini.app"

    launcher = bin/"mic-mini"
    launcher.write <<~SH
      #!/bin/sh
      exec /usr/bin/open "#{opt_prefix}/Mic Mini.app"
    SH
    launcher.chmod 0755
  end

  test do
    assert_predicate bin/"mic-mini", :executable?
    system "/usr/bin/codesign", "--verify", "--strict", prefix/"Mic Mini.app"
  end
end
EOF

git -C "$tap_source" add --all -- Formula artifacts
if ! git -C "$tap_source" diff --cached --quiet; then
    git -C "$tap_source" -c user.name="Mic Mini" -c user.email=local@localhost \
        -c commit.gpgSign=false -c core.hooksPath=/dev/null commit --quiet -m "Package Mic Mini $version"
fi

brew tap "$tap" "$tap_source"
git -C "$tap_dir" -c core.hooksPath=/dev/null pull --quiet --ff-only
brew trust --formula "$formula"

action=install
if brew list --formula "$formula" >/dev/null 2>&1; then
    action=reinstall
fi
brew "$action" --formula --no-ask "$@" "$formula"
