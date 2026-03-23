class Simu < Formula
  desc 'CLI tool to manage iOS simulators and Android emulators on macOS'
  homepage 'https://github.com/yefga/Simu'
  url 'https://github.com/yefga/Simu/archive/refs/tags/v0.2.0.tar.gz'
  sha256 '7760f4347bae44ced8b12820c2c6939baf048a5f22d7ddca5c385bd17adcb91b'
  license 'MIT'

  depends_on 'ruby'

  def install
    ENV['GEM_HOME'] = libexec
    system 'gem', 'build', 'simu.gemspec'
    system 'gem', 'install', 'simu-0.2.0.gem'
    bin.install libexec/'bin/simu'
    bin.env_script_all_files(libexec/'bin', GEM_HOME: ENV['GEM_HOME'])
  end

  test do
    assert_match 'version', shell_output("#{bin}/simu version")
  end
end
