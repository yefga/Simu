class Simu < Formula
  desc 'CLI tool to manage iOS simulators and Android emulators on macOS'
  homepage 'https://github.com/yefga/Simu'
  url 'https://github.com/yefga/Simu/archive/refs/tags/v0.1.0.tar.gz'
  sha256 '152a7cf4271c88fc85e07c8e643a090851743c57ac852534c43129b6bfd53554'
  license 'MIT'

  depends_on 'ruby'

  def install
    ENV['GEM_HOME'] = libexec
    system 'gem', 'build', 'simu.gemspec'
    system 'gem', 'install', 'simu-0.1.0.gem'
    bin.install libexec/'bin/simu'
    bin.env_script_all_files(libexec/'bin', GEM_HOME: ENV['GEM_HOME'])
  end

  test do
    assert_match 'version', shell_output("#{bin}/simu version")
  end
end
