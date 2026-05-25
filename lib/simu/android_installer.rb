# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'net/http'
require 'open3'
require 'openssl'
require 'tmpdir'
require 'uri'

module Simu
  # Installs a private Android SDK/runtime and creates a compatible virtual device.
  class AndroidInstaller
    class SetupError < StandardError; end

    COMMANDLINE_TOOLS = {
      macos: {
        url: 'https://dl.google.com/android/repository/commandlinetools-mac-14742923_latest.zip',
        sha256: 'ed304c5ede3718541e4f978e4ae870a4d853db74af6c16d920588d48523b9dee'
      },
      linux: {
        url: 'https://dl.google.com/android/repository/commandlinetools-linux-14742923_latest.zip',
        sha256: '04453066b540409d975c676d781da1477479dde3761310f1a7eb92a1dfb15af7'
      }
    }.freeze
    BUILD_TOOLS_PACKAGE = 'build-tools;36.0.0'
    CORE_PACKAGES = ['emulator', 'platform-tools', BUILD_TOOLS_PACKAGE].freeze

    def initialize(prompt: Simu::UI.prompt, host: Simu::AndroidToolchain.host,
                   toolchain: Simu::AndroidToolchain.managed)
      @prompt = prompt
      @host = host
      @toolchain = toolchain
    end

    def setup!
      ensure_supported_host!

      existing = Simu::AndroidToolchain.external
      if existing
        Simu::UI.success("A usable Android SDK is already available at #{existing.sdk_root || 'your PATH'}.")
        return existing unless @prompt.yes?('Create a separate Simu-managed Android emulator setup anyway?')
      end

      preflight!
      confirm_downloads!
      prepare_directories!
      install_java! unless @toolchain.java_bin
      install_commandline_tools! unless File.executable?(@toolchain.sdkmanager_bin)
      accept_licenses!
      install_sdk_packages(*CORE_PACKAGES)

      image = select_system_image
      install_sdk_packages(image)
      device = select_device_profile
      avd_name = create_or_reuse_avd(image, device)

      fail_setup('Managed Android tooling could not be verified after installation.') unless @toolchain.usable?

      accelerated, detail = @toolchain.acceleration_status
      if accelerated
        Simu::UI.success("Emulator acceleration verified: #{detail}")
      else
        Simu::UI.warning("Emulator acceleration could not be verified: #{detail}")
      end

      Simu::UI.success("Android setup complete. Run: simu android run #{avd_name}")
      @toolchain
    rescue SetupError => e
      Simu::UI.error(e.message)
    rescue StandardError => e
      Simu::UI.error("Android setup failed: #{e.message}")
    end

    private

    def ensure_supported_host!
      return if Simu::AndroidToolchain.supported_host?(@host)

      fail_setup(Simu::AndroidToolchain.unsupported_host_message(@host))
    end

    def preflight!
      missing = %w[tar unzip].reject { |command| Simu::AndroidToolchain.find_in_path(command) }
      return if missing.empty?

      fail_setup("Required archive tools are missing: #{missing.join(', ')}.")
    end

    def confirm_downloads!
      Simu::UI.info("Simu will store Android tooling under #{Simu::AndroidToolchain.simu_home}/android.")
      Simu::UI.info('Setup downloads a private Temurin 25 Java runtime, Android SDK tools, an emulator,')
      Simu::UI.info('and a system image; allow several GB of disk space.')
      terms = 'Proceed and review/accept the Android SDK licenses during installation?'
      fail_setup('Setup cancelled.') unless @prompt.yes?(terms)
    end

    def prepare_directories!
      [
        @toolchain.sdk_root,
        @toolchain.avd_home,
        Simu::AndroidToolchain.managed_user_home,
        Simu::AndroidToolchain.managed_runtime_root,
        download_root
      ].each { |directory| FileUtils.mkdir_p(directory) }
    end

    def install_java!
      Simu::UI.info('Downloading private Eclipse Temurin JRE 25 for Android setup...')
      metadata = fetch_json(temurin_metadata_url)
      package = metadata.first&.dig('binary', 'package')
      fail_setup('Could not obtain a compatible Eclipse Temurin JRE download.') unless package

      archive = File.join(download_root, File.basename(URI(package.fetch('link')).path))
      download_file(
        package.fetch('link'),
        archive,
        package.fetch('checksum'),
        label: 'Eclipse Temurin JRE 25'
      )

      stage = Dir.mktmpdir('java-', Simu::AndroidToolchain.managed_runtime_root)
      unless system('tar', '-xzf', archive, '-C', stage, out: File::NULL, err: File::NULL)
        fail_setup('Could not extract the private Java runtime.')
      end

      java = Dir.glob(File.join(stage, '**', 'bin', 'java')).find { |path| File.executable?(path) }
      fail_setup('The downloaded Java runtime did not contain an executable Java binary.') unless java

      current = File.join(Simu::AndroidToolchain.managed_runtime_root, 'current')
      FileUtils.rm_rf(current)
      FileUtils.mv(stage, current)
      Simu::UI.success('Private Java runtime installed.')
    ensure
      FileUtils.rm_rf(stage) if stage && File.directory?(stage)
    end

    def install_commandline_tools!
      package = COMMANDLINE_TOOLS.fetch(@host.os)
      Simu::UI.info('Downloading Android SDK command-line tools...')
      archive = File.join(download_root, File.basename(URI(package.fetch(:url)).path))
      download_file(
        package.fetch(:url),
        archive,
        package.fetch(:sha256),
        label: 'Android SDK command-line tools'
      )

      stage = Dir.mktmpdir('cmdline-tools-', download_root)
      unless system('unzip', '-q', archive, '-d', stage, out: File::NULL, err: File::NULL)
        fail_setup('Could not extract Android SDK command-line tools.')
      end

      extracted = File.join(stage, 'cmdline-tools')
      sdkmanager = File.join(extracted, 'bin', 'sdkmanager')
      unless File.executable?(sdkmanager)
        fail_setup('The Android SDK command-line tools archive has an unexpected layout.')
      end

      target = File.join(@toolchain.sdk_root, 'cmdline-tools', 'latest')
      FileUtils.mkdir_p(File.dirname(target))
      FileUtils.rm_rf(target)
      FileUtils.mv(extracted, target)
      Simu::UI.success('Android SDK command-line tools installed.')
    ensure
      FileUtils.rm_rf(stage) if stage && File.directory?(stage)
    end

    def accept_licenses!
      Simu::UI.info('Review and accept the Android SDK licenses to continue.')
      success = system(@toolchain.environment(include_java: true), @toolchain.sdkmanager_bin,
                       "--sdk_root=#{@toolchain.sdk_root}", '--licenses')
      fail_setup('Android SDK licenses were not accepted.') unless success
    end

    def install_sdk_packages(*packages)
      Simu::UI.info("Installing Android SDK packages: #{packages.join(', ')}")
      Simu::UI.info('Android SDK Manager will display download and installation progress below.')
      success = system(@toolchain.environment(include_java: true), @toolchain.sdkmanager_bin,
                       "--sdk_root=#{@toolchain.sdk_root}", *packages)
      fail_setup('Android SDK package installation failed.') unless success
    end

    def select_system_image
      output, error, status = Open3.capture3(
        @toolchain.environment(include_java: true),
        @toolchain.sdkmanager_bin,
        "--sdk_root=#{@toolchain.sdk_root}",
        '--list',
        '--channel=0'
      )
      fail_setup("Could not list Android system images. #{error.strip}") unless status.success?

      images = compatible_images(output)
      fail_setup("No compatible Android system image was found for #{@host.label}.") if images.empty?

      choices = images.map.with_index do |image, index|
        label = image_label(image)
        label += ' (recommended)' if index.zero?
        { name: label, value: image }
      end
      @prompt.select('Choose an Android system image:', choices, per_page: 15)
    end

    def compatible_images(output)
      required_arch = @host.arch == :arm64 ? 'arm64-v8a' : 'x86_64'
      variants = '(?:google_apis|google_apis_playstore|default)'
      pattern = /\Asystem-images;android-\d+;#{variants};#{Regexp.escape(required_arch)}\z/
      images = output.lines.map { |line| line.split('|').first.to_s.strip }
                     .grep(pattern)
                     .uniq

      images.sort_by do |image|
        parts = image.split(';')
        api = parts[1].delete_prefix('android-').to_i
        variant_rank = {
          'google_apis' => 0,
          'google_apis_playstore' => 1,
          'default' => 2
        }.fetch(parts[2], 3)
        [-api, variant_rank]
      end
    end

    def image_label(image)
      _prefix, api, variant, architecture = image.split(';')
      variant_name = {
        'google_apis' => 'Google APIs',
        'google_apis_playstore' => 'Google Play',
        'default' => 'Android Open Source'
      }.fetch(variant, variant)
      "#{api.tr('-', ' ').capitalize} - #{variant_name} (#{architecture})"
    end

    def select_device_profile
      output, error, status = Open3.capture3(
        @toolchain.environment(include_java: true),
        @toolchain.avdmanager_bin,
        'list',
        'device'
      )
      fail_setup("Could not list Android device profiles. #{error.strip}") unless status.success?

      devices = output.scan(/id:\s+\d+\s+or\s+"([^"]+)"\s*\n\s+Name:\s+([^\n]+)/).map do |id, name|
        { name: name.strip, value: id }
      end
      phones = devices.reject { |device| device[:name].match?(/wear|tv|automotive|desktop/i) }
      fail_setup('No Android phone device profiles were available.') if phones.empty?

      @prompt.select('Choose an Android phone profile:', phones, per_page: 15)
    end

    def create_or_reuse_avd(image, device)
      name = avd_name(image, device)
      if @toolchain.avd_names.include?(name)
        if matching_avd?(name, image)
          Simu::UI.success("Using existing Android emulator: #{name}")
          return name
        end

        overwrite = @prompt.yes?("An emulator named #{name} already exists with different settings. Replace it?")
        fail_setup('Setup cancelled because the selected emulator name is already in use.') unless overwrite
      end

      FileUtils.mkdir_p(@toolchain.avd_home)
      stdin, stdout, stderr, wait = Open3.popen3(
        @toolchain.environment(include_java: true),
        @toolchain.avdmanager_bin,
        'create', 'avd', '--force', '--name', name, '--package', image, '--device', device
      )
      stdin.puts('no')
      stdin.close
      message = stdout.read + stderr.read
      fail_setup("Could not create Android emulator #{name}: #{message.strip}") unless wait.value.success?

      Simu::UI.success("Created Android emulator: #{name}")
      name
    end

    def matching_avd?(name, image)
      config = File.join(@toolchain.avd_home, "#{name}.avd", 'config.ini')
      return false unless File.file?(config)

      expected = image.split(';').drop(1).join(File::SEPARATOR)
      File.read(config).tr('\\', File::SEPARATOR).include?(expected)
    end

    def avd_name(image, device)
      api = image.split(';')[1].delete_prefix('android-')
      safe_device = device.gsub(/[^a-zA-Z0-9_]+/, '_').downcase
      "simu_#{safe_device}_api_#{api}"
    end

    def temurin_metadata_url
      os = @host.os == :macos ? 'mac' : 'linux'
      arch = @host.arch == :arm64 ? 'aarch64' : 'x64'
      'https://api.adoptium.net/v3/assets/latest/25/hotspot' \
        "?architecture=#{arch}&heap_size=normal&image_type=jre&jvm_impl=hotspot&os=#{os}" \
        '&project=jdk&vendor=eclipse'
    end

    def download_root
      File.join(Simu::AndroidToolchain.simu_home, 'android', 'downloads')
    end

    def fetch_json(url)
      body = +''
      with_http_response(url) { |response| response.read_body { |chunk| body << chunk } }
      JSON.parse(body)
    end

    def download_file(url, destination, expected_sha256, label:)
      checksum = expected_sha256.downcase
      if File.file?(destination) && Digest::SHA256.file(destination).hexdigest == checksum
        Simu::UI.success("Using cached download: #{label}.")
        return
      end

      temporary = "#{destination}.download"
      FileUtils.rm_f(temporary)
      spinner = download_spinner(label)
      spinner.update(progress: download_progress(0))
      spinner.auto_spin
      downloaded = 0
      File.open(temporary, 'wb') do |file|
        with_http_response(url) do |response|
          total = content_length(response)
          response.read_body do |chunk|
            file.write(chunk)
            downloaded += chunk.bytesize
            spinner.update(progress: download_progress(downloaded, total))
          end
        end
      end

      actual = Digest::SHA256.file(temporary).hexdigest
      fail_setup("Checksum verification failed for #{File.basename(destination)}.") unless actual == checksum

      FileUtils.mv(temporary, destination)
      spinner.success('Downloaded and verified.')
    rescue StandardError
      spinner&.error('Download failed.')
      raise
    ensure
      FileUtils.rm_f(temporary) if temporary && File.file?(temporary)
    end

    def download_spinner(label)
      TTY::Spinner.new("[:spinner] Downloading #{label}: :progress", format: :classic)
    end

    def content_length(response)
      length = response['content-length'].to_i
      length.positive? ? length : nil
    end

    def download_progress(downloaded, total = nil)
      downloaded_text = download_size(downloaded)
      return "#{downloaded_text} downloaded" unless total

      percent = [(downloaded * 100.0 / total).floor, 100].min
      "#{percent.to_s.rjust(3)}% (#{downloaded_text} / #{download_size(total)})"
    end

    def download_size(bytes)
      return '0 B' if bytes.zero?

      Simu::Utils.format_size(bytes)
    end

    def with_http_response(url, redirects = 5, &block)
      fail_setup("Too many redirects while downloading #{url}.") if redirects.zero?

      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER if http.use_ssl?

      request = Net::HTTP::Get.new(uri.request_uri)
      http.request(request) do |response|
        case response
        when Net::HTTPSuccess
          block.call(response)
        when Net::HTTPRedirection
          location = URI.join(url, response['location']).to_s
          return with_http_response(location, redirects - 1, &block)
        else
          fail_setup("Download failed for #{url}: HTTP #{response.code}.")
        end
      end
    end

    def fail_setup(message)
      raise SetupError, message
    end
  end
end
