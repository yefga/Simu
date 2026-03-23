class Simu < Formula
  desc 'CLI tool to manage iOS simulators and Android emulators on macOS'
  homepage 'https://github.com/yefga/Simu'
  url 'https://github.com/yefga/Simu/archive/refs/tags/v0.1.2.tar.gz'
  sha256 '816747e4fb273210f6b517d7cab8884de27f16eedccbce39643489f1607cb3c1'
  license 'MIT'

  depends_on 'ruby'

  def install
    ENV['GEM_HOME'] = libexec
    system 'gem', 'build', 'simu.gemspec'
    system 'gem', 'install', 'simu-0.1.2.gem'
    bin.install libexec/'bin/simu'
    bin.env_script_all_files(libexec/'bin', GEM_HOME: ENV['GEM_HOME'])
  end

  test do
    assert_match 'version', shell_output("#{bin}/simu version")
  end
end
