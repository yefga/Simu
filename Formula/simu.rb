class Simu < Formula
  desc 'CLI tool to manage iOS simulators and Android emulators on macOS'
  homepage 'https://github.com/yefga/Simu'
  url 'https://github.com/yefga/Simu/archive/refs/tags/v0.3.0.tar.gz'
  sha256 '030438b4ca3fbbc11ff8cbaba5da4b67d58a8aeb4bcc687002016da10c85b1ed'
  license 'MIT'

  depends_on 'ruby'

  def install
    ENV['GEM_HOME'] = libexec
    system 'gem', 'build', 'simu.gemspec'
    system 'gem', 'install', 'simu-0.3.0.gem'
    bin.install libexec/'bin/simu'
    bin.env_script_all_files(libexec/'bin', GEM_HOME: ENV['GEM_HOME'])
  end

  test do
    assert_match 'version', shell_output("#{bin}/simu version")
  end
end
