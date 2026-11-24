class MicMini < Formula
  desc "Notch voice recorder for your goldfish memory"
  homepage "https://github.com/flol3622/mic-mini"
  url "https://github.com/flol3622/mic-mini.git", tag: "v0.2.0"
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
      Then hover at the center of the notch. Mic Mini opens at login from then on;
      turn that off in its Settings before you uninstall.
    EOS
  end

  test do
    assert_predicate bin/"mic-mini", :executable?
    system "/usr/bin/codesign", "--verify", "--strict", prefix/"Mic Mini.app"
  end
end
