#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd -P)"
tap="fishmic/local"
formula="$tap/fishmic"
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
COPYFILE_DISABLE=1 tar -czf "$staging/FishMic.tar.gz" -C "$project_dir" Sources app scripts/build.sh
checksum="$(shasum -a 256 "$staging/FishMic.tar.gz" | cut -d ' ' -f 1)"
archive="FishMic-$checksum.tar.gz"
rm -f "$tap_source"/artifacts/FishMic-*.tar.gz
mv "$staging/FishMic.tar.gz" "$tap_source/artifacts/$archive"

cat > "$tap_source/Formula/fishmic.rb" <<EOF
class Fishmic < Formula
  desc "Menu bar voice recorder for your goldfish memory"
  homepage "file://#{URI::DEFAULT_PARSER.escape("#{HOMEBREW_LIBRARY}/Taps/fishmic/homebrew-local")}"
  url "#{homepage}/artifacts/$archive"
  version "$version"
  sha256 "$checksum"

  depends_on "lame"
  depends_on macos: :tahoe

  def install
    ENV["LAME_PREFIX"] = Formula["lame"].opt_prefix
    system "./scripts/build.sh"
    prefix.install "dist/FishMic.app"

    launcher = bin/"fishmic"
    launcher.write <<~SH
      #!/bin/sh
      exec /usr/bin/open "#{opt_prefix}/FishMic.app"
    SH
    launcher.chmod 0755
  end

  test do
    assert_predicate bin/"fishmic", :executable?
    system "/usr/bin/codesign", "--verify", "--strict", prefix/"FishMic.app"
  end
end
EOF

git -C "$tap_source" add --all -- Formula artifacts
if ! git -C "$tap_source" diff --cached --quiet; then
    git -C "$tap_source" -c user.name="FishMic" -c user.email=local@localhost \
        -c commit.gpgSign=false -c core.hooksPath=/dev/null commit --quiet -m "Package FishMic $version"
fi

brew tap "$tap" "$tap_source"
git -C "$tap_dir" -c core.hooksPath=/dev/null pull --quiet --ff-only
brew trust --formula "$formula"

# Homebrew can't hold the same formula from two taps, so swap out the public one.
installed="$(brew list --formula --full-name | grep -E '(^|/)fishmic$' || true)"
if [[ -n "$installed" && "$installed" != "$formula" ]]; then
    printf 'Replacing %s with this checkout\n' "$installed"
    brew uninstall --formula "$installed"
fi

action=install
if brew list --formula "$formula" >/dev/null 2>&1; then
    action=reinstall
fi
brew "$action" --formula --no-ask "$@" "$formula"
