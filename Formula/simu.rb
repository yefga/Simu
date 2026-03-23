class Simu < Formula
  desc 'CLI tool to manage iOS simulators and Android emulators on macOS'
  homepage 'https://github.com/yefga/Simu'
  url 'https://github.com/yefga/Simu/archive/refs/tags/v0.1.0.tar.gz'
  sha256 '8d4f6e82e604b7e588b0d082243e499118f460d8cf626d8e1db164e609711978'
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
