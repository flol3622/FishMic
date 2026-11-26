class MicMini < Formula
  desc "Menu bar voice recorder for your goldfish memory"
  homepage "https://github.com/flol3622/mic-mini"
  url "https://github.com/flol3622/mic-mini.git", tag: "v0.3.1"
  license "MIT"
  head "https://github.com/flol3622/mic-mini.git", branch: "main"

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

  def caveats
    <<~EOS
      Start Mic Mini with:
        mic-mini
      Then click the fish in the menu bar. Mic Mini opens at login from then on,
      and adds a launcher to ~/Applications so ⌘Space can find it.
      Before you uninstall, turn off Open at login in its Settings; afterwards:
        rm -rf ~/Applications/"Mic Mini.app"
    EOS
  end

  test do
    assert_predicate bin/"mic-mini", :executable?
    system "/usr/bin/codesign", "--verify", "--strict", prefix/"Mic Mini.app"
  end
end
