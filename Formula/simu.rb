class Simu < Formula
  desc "CLI tool to manage Apple simulators and Android emulators"
  homepage "https://github.com/yefga/Simu"
  url "https://github.com/yefga/Simu/archive/refs/tags/v0.4.0.tar.gz"
  sha256 "8ebdf949a8dfbf91156496c52e967c6616b15e049f40a550962e2339488caf53"
  license "MIT"

  depends_on "ruby"

  def install
    ENV["GEM_HOME"] = libexec
    system "gem", "build", "simu.gemspec"
    system "gem", "install", "simu-0.4.0.gem"
    bin.install libexec/"bin/simu"
    bin.env_script_all_files(libexec/"bin", GEM_HOME: ENV["GEM_HOME"])
  end

  test do
    assert_match "0.4.0", shell_output("#{bin}/simu version")
  end
end
