class Fishmic < Formula
  desc "Menu bar voice recorder for your goldfish memory"
  homepage "https://github.com/flol3622/FishMic"
  url "https://github.com/flol3622/FishMic.git", tag: "v0.4.0"
  license "MIT"
  head "https://github.com/flol3622/FishMic.git", branch: "main"

  depends_on macos: :tahoe

  def install
    system "./scripts/build.sh"
    prefix.install "dist/FishMic.app"

    launcher = bin/"fishmic"
    launcher.write <<~SH
      #!/bin/sh
      exec /usr/bin/open "#{opt_prefix}/FishMic.app"
    SH
    launcher.chmod 0755
  end

  def caveats
    <<~EOS
      Start FishMic with:
        fishmic
      Then click the fish in the menu bar. FishMic opens at login from then on,
      and adds a launcher to ~/Applications so ⌘Space can find it.
      Before you uninstall, turn off Open at login in its Settings; afterwards:
        rm -rf ~/Applications/"FishMic.app"
    EOS
  end

  test do
    assert_predicate bin/"fishmic", :executable?
    system "/usr/bin/codesign", "--verify", "--strict", prefix/"FishMic.app"
  end
end
