#!/usr/bin/env ruby
# frozen_string_literal: true

# Fetch a checksum-pinned Homebrew bottle closure into an isolated prefix.
# This is a maintainer supply-chain helper for building the bundled Qt archive.

require 'digest'
require 'fileutils'
require 'find'
require 'json'
require 'net/http'
require 'openssl'
require 'open3'
require 'optparse'
require 'shellwords'
require 'tempfile'
require 'tmpdir'
require 'timeout'
require 'uri'

module WormsBottleFetcher
  DEFAULT_FORMULA = 'qt@5'
  DEFAULT_TAG = 'sonoma'
  LOCK_HEADER = %w[name version bottle_tag bottle_sha256 bottle_url source_sha256 ruby_source_sha256 tap_git_head].freeze
  ALLOWED_FORMULAE = %w[
    qt@5 freetype glib jpeg-turbo libpng libtiff md4c pcre2 sqlite webp zstd
    gettext xz readline giflib lz4 libunistring
  ].freeze
  MAX_LOCK_BYTES = 65_536
  MAX_LOCK_ROWS = 64
  MAX_JSON_BYTES = 4 * 1024 * 1024
  MAX_BOTTLE_BYTES = 256 * 1024 * 1024
  MAX_REDIRECTS = 5
  MARKER_NAME = '.wormswmd-bottle-prefix-v1'
  REPO_ROOT = File.expand_path('..', __dir__)
  DEFAULT_LOCK = File.join(REPO_ROOT, 'packaging', 'qt-homebrew-lock.tsv')
  INSPECTOR = File.join(__dir__, 'inspect_archive.py')
  SHA256_RE = /\A[0-9a-f]{64}\z/.freeze
  SHA1_RE = /\A[0-9a-f]{40}\z/.freeze
  NAME_RE = /\A[A-Za-z0-9][A-Za-z0-9@+_.-]*\z/.freeze
  VERSION_RE = /\A[0-9][0-9A-Za-z.+_-]{0,127}\z/.freeze
  TAG_RE = /\A[a-z0-9][a-z0-9_]{0,31}\z/.freeze
  REDIRECT_CODES = [301, 302, 303, 307, 308].freeze
  SYSTEM_PREFIXES = %w[/System /Library /Applications /usr /bin /sbin /etc].freeze
  SYSTEM_EXACT = %w[/var /private /tmp].freeze

  OutputTarget = Struct.new(:path, :state, keyword_init: true)

  class Error < StandardError; end

  module_function

  def run!(*command)
    raise Error, "Command failed: #{command.shelljoin}" unless system(*command)
  end

  def capture!(*command, max_bytes: 64 * 1024 * 1024)
    output, status = Open3.capture2e(*command)
    raise Error, "Command output exceeded #{max_bytes} bytes: #{command.shelljoin}" if output.bytesize > max_bytes
    raise Error, "Command failed: #{command.shelljoin}\n#{output}" unless status.success?
    output
  end

  def regular_file!(path, label, max_bytes: nil)
    stat = File.lstat(path)
    raise Error, "#{label} must be a regular, non-symlink file: #{path}" unless stat.file? && !stat.symlink?
    raise Error, "#{label} exceeds #{max_bytes} bytes" if max_bytes && stat.size > max_bytes
    stat
  rescue Errno::ENOENT
    raise Error, "#{label} not found: #{path}"
  end

  def bounded_read(path, label, max_bytes)
    regular_file!(path, label, max_bytes: max_bytes)
    data = File.open(path, 'rb') { |file| file.read(max_bytes + 1) }
    raise Error, "#{label} exceeds #{max_bytes} bytes" if data.bytesize > max_bytes
    data
  end

  def bounded_sha256(path, label, max_bytes)
    regular_file!(path, label, max_bytes: max_bytes)
    digest = Digest::SHA256.new
    total = 0
    File.open(path, 'rb') do |file|
      while (chunk = file.read(1024 * 1024))
        total += chunk.bytesize
        raise Error, "#{label} exceeds #{max_bytes} bytes" if total > max_bytes
        digest.update(chunk)
      end
    end
    digest.hexdigest
  end

  def expected_bottle_path(entry)
    formula_path = entry.fetch('name').tr('@', '/')
    "/v2/homebrew/core/#{formula_path}/blobs/sha256:#{entry.fetch('bottle_sha256')}"
  end

  def validate_lock_entry!(entry)
    name = entry.fetch('name')
    raise Error, "Formula is not allowlisted: #{name}" unless NAME_RE.match?(name) && ALLOWED_FORMULAE.include?(name)
    raise Error, "Invalid version for #{name}" unless VERSION_RE.match?(entry.fetch('version'))
    raise Error, "Invalid bottle tag for #{name}" unless TAG_RE.match?(entry.fetch('bottle_tag'))
    raise Error, "Unsupported bottle tag for #{name}" unless entry.fetch('bottle_tag') == DEFAULT_TAG
    %w[bottle_sha256 source_sha256 ruby_source_sha256].each do |field|
      raise Error, "Invalid #{field} for #{name}" unless SHA256_RE.match?(entry.fetch(field))
    end
    raise Error, "Invalid tap_git_head for #{name}" unless SHA1_RE.match?(entry.fetch('tap_git_head'))

    uri = URI.parse(entry.fetch('bottle_url'))
    unless uri.is_a?(URI::HTTPS) && uri.host == 'ghcr.io' && uri.port == 443 &&
           uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil? && uri.path == expected_bottle_path(entry)
      raise Error, "Invalid GHCR bottle URL for #{name}"
    end
  rescue URI::InvalidURIError
    raise Error, "Invalid GHCR bottle URL for #{name}"
  end

  def validate_entries!(entries, require_complete: true)
    raise Error, 'Bottle lock contains no rows' if entries.empty?
    raise Error, "Bottle lock exceeds #{MAX_LOCK_ROWS} rows" if entries.length > MAX_LOCK_ROWS
    names = {}
    entries.each do |entry|
      validate_lock_entry!(entry)
      name = entry.fetch('name')
      raise Error, "Duplicate formula in bottle lock: #{name}" if names[name]
      names[name] = true
    end
    if require_complete && names.keys.sort != ALLOWED_FORMULAE.sort
      missing = ALLOWED_FORMULAE - names.keys
      extra = names.keys - ALLOWED_FORMULAE
      raise Error, "Bottle lock closure mismatch (missing=#{missing.join(',')} extra=#{extra.join(',')})"
    end
    entries
  end

  def read_lock(path, require_complete: true)
    regular_file!(path, 'Bottle lock', max_bytes: MAX_LOCK_BYTES)
    bytes = bounded_read(path, 'Bottle lock', MAX_LOCK_BYTES)
    raise Error, "Bottle lock is not valid UTF-8: #{path}" unless bytes.dup.force_encoding(Encoding::UTF_8).valid_encoding?
    lines = bytes.force_encoding(Encoding::UTF_8).lines(chomp: true)
    data_lines = lines.reject { |line| line.empty? || line.start_with?('#') }
    header = data_lines.shift&.split("\t", -1)
    raise Error, "Invalid lock header in #{path}" unless header == LOCK_HEADER
    entries = data_lines.map do |line|
      raise Error, 'Invalid control character in lock row' if line.match?(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/)
      values = line.split("\t", -1)
      raise Error, "Invalid lock row field count in #{path}" unless values.length == LOCK_HEADER.length
      raise Error, 'Bottle lock fields may not be empty' if values.any?(&:empty?)
      LOCK_HEADER.zip(values).to_h
    end
    validate_entries!(entries, require_complete: require_complete)
  end

  def write_lock(path, entries)
    validate_entries!(entries)
    expanded = File.expand_path(path)
    parent = File.dirname(expanded)
    raise Error, "Lock output parent must already exist: #{parent}" unless File.directory?(parent)
    raise Error, "Lock output parent may not be a symlink: #{parent}" if File.symlink?(parent)
    path = File.join(File.realpath(parent), File.basename(expanded))
    if File.exist?(path) || File.symlink?(path)
      raise Error, "Refusing to overwrite candidate lock output: #{path}"
    end
    temporary = Tempfile.new(['.wormswmd-lock-', '.tsv'], parent)
    begin
      temporary.chmod(0o600)
      temporary.puts '# WormsWMD Homebrew bottle lock v1'
      temporary.puts "# generated_utc\t#{Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')}"
      temporary.puts LOCK_HEADER.join("\t")
      entries.each { |entry| temporary.puts LOCK_HEADER.map { |key| entry.fetch(key) }.join("\t") }
      temporary.flush
      temporary.fsync
      temporary.close
      File.rename(temporary.path, path)
    ensure
      temporary.close! if File.exist?(temporary.path)
    end
  end

  def origin(uri)
    [uri.scheme, uri.host, uri.port]
  end

  def allowed_download_host?(host)
    host == 'ghcr.io' || host == 'pkg-containers.githubusercontent.com' ||
      host.end_with?('.pkg-containers.githubusercontent.com') || host.end_with?('.githubusercontent.com')
  end

  def validate_https_uri!(uri, allowed_host)
    unless uri.is_a?(URI::HTTPS) && uri.port == 443 && uri.userinfo.nil? &&
           uri.fragment.nil? && allowed_host.call(uri.host.to_s)
      raise Error, "Unapproved HTTPS origin: #{uri}"
    end
    uri
  end

  def redirect_target(current, location, authorization_origin)
    raise Error, 'Redirect response omitted Location' if location.to_s.empty?
    target = URI.join(current.to_s, location)
    validate_https_uri!(target, method(:allowed_download_host?))
    [target, authorization_origin && origin(target) == origin(authorization_origin)]
  rescue URI::InvalidURIError
    raise Error, 'Redirect response contained an invalid Location'
  end

  def http_response(uri, headers = {})
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    if http.respond_to?(:min_version=) && defined?(OpenSSL::SSL::TLS1_2_VERSION)
      http.min_version = OpenSSL::SSL::TLS1_2_VERSION
    end
    http.open_timeout = 15
    http.read_timeout = 90
    request_headers = {
      'Accept-Encoding' => 'identity',
      'User-Agent' => 'WormsWMD-macOS-Fix bottle fetcher'
    }.merge(headers)
    request = Net::HTTP::Get.new(uri.request_uri, request_headers)
    http.request(request) { |response| yield response }
  end

  def fetch_bytes(uri, max_bytes:, allowed_host:)
    current = validate_https_uri!(uri, allowed_host)
    redirects = 0
    loop do
      result = nil
      http_response(current) do |response|
        if REDIRECT_CODES.include?(response.code.to_i)
          redirects += 1
          raise Error, "Redirect limit exceeded for #{uri.host}" if redirects > MAX_REDIRECTS
          current = URI.join(current.to_s, response['location'].to_s)
          validate_https_uri!(current, allowed_host)
          result = :redirect
          next
        end
        raise Error, "HTTP #{response.code} from #{current.host}" unless response.is_a?(Net::HTTPSuccess)
        length = response['content-length'].to_i
        raise Error, "Response from #{current.host} exceeds #{max_bytes} bytes" if length > max_bytes
        body = +''
        response.read_body do |chunk|
          body << chunk
          raise Error, "Response from #{current.host} exceeds #{max_bytes} bytes" if body.bytesize > max_bytes
        end
        result = body
      end
      return result unless result == :redirect
    end
  rescue URI::InvalidURIError
    raise Error, "Invalid redirect from #{uri.host}"
  end

  def fetch_json(formula)
    encoded = URI.encode_www_form_component(formula)
    uri = URI("https://formulae.brew.sh/api/formula/#{encoded}.json")
    JSON.parse(fetch_bytes(uri, max_bytes: MAX_JSON_BYTES, allowed_host: ->(host) { host == 'formulae.brew.sh' }))
  rescue JSON::ParserError
    raise Error, "Formula metadata was not valid JSON: #{formula}"
  end

  def ghcr_token(repo)
    query = URI.encode_www_form(service: 'ghcr.io', scope: "repository:#{repo}:pull")
    uri = URI("https://ghcr.io/token?#{query}")
    data = fetch_bytes(uri, max_bytes: MAX_JSON_BYTES, allowed_host: ->(host) { host == 'ghcr.io' })
    token = JSON.parse(data).fetch('token')
    unless token.is_a?(String) && token.bytesize.between?(1, 16_384) && !token.match?(/[\x00-\x20\x7f]/)
      raise Error, 'GHCR returned an invalid bearer token'
    end
    token
  rescue JSON::ParserError, KeyError
    raise Error, 'GHCR token response was invalid'
  end

  def stream_bottle(uri, destination, token)
    current = validate_https_uri!(uri, method(:allowed_download_host?))
    authorization_origin = uri
    redirects = 0
    digest = Digest::SHA256.new
    bytes = 0
    loop do
      followed = false
      headers = {}
      if authorization_origin && origin(current) == origin(authorization_origin)
        headers['Authorization'] = "Bearer #{token}"
      end
      http_response(current, headers) do |response|
        if REDIRECT_CODES.include?(response.code.to_i)
          redirects += 1
          raise Error, "Redirect limit exceeded for #{uri.host}" if redirects > MAX_REDIRECTS
          current, keep_authorization = redirect_target(
            current, response['location'], authorization_origin
          )
          authorization_origin = nil unless keep_authorization
          followed = true
          next
        end
        raise Error, "HTTP #{response.code} from #{current.host}" unless response.is_a?(Net::HTTPSuccess)
        length = response['content-length'].to_i
        raise Error, "Bottle exceeds #{MAX_BOTTLE_BYTES} bytes" if length > MAX_BOTTLE_BYTES
        File.open(destination, 'wb', 0o600) do |file|
          response.read_body do |chunk|
            bytes += chunk.bytesize
            raise Error, "Bottle exceeds #{MAX_BOTTLE_BYTES} bytes" if bytes > MAX_BOTTLE_BYTES
            digest.update(chunk)
            file.write(chunk)
          end
          file.flush
          file.fsync
        end
      end
      return [digest.hexdigest, bytes] unless followed
    end
  end

  def safe_cache_directory(path)
    expanded = File.expand_path(path)
    if File.exist?(expanded) || File.symlink?(expanded)
      stat = File.lstat(expanded)
      raise Error, "Cache must be a non-symlink directory: #{expanded}" unless stat.directory? && !stat.symlink?
    else
      FileUtils.mkdir_p(expanded, mode: 0o700)
    end
    File.realpath(expanded)
  end

  def cache_filename(entry)
    "#{entry.fetch('name').tr('/', '_')}--#{entry.fetch('version')}.#{entry.fetch('bottle_tag')}.bottle.tar.gz"
  end

  def download_blob(entry, cache_dir, token_cache)
    out = File.join(cache_dir, cache_filename(entry))
    if File.exist?(out) || File.symlink?(out)
      regular_file!(out, 'Cached bottle', max_bytes: MAX_BOTTLE_BYTES)
      actual = bounded_sha256(out, 'Cached bottle', MAX_BOTTLE_BYTES)
      raise Error, "Cached bottle checksum mismatch for #{entry.fetch('name')}" unless actual == entry.fetch('bottle_sha256')
      return out
    end
    uri = URI(entry.fetch('bottle_url'))
    repo = uri.path[%r{\A/v2/(.+)/blobs/sha256:[0-9a-f]{64}\z}, 1]
    raise Error, "Cannot parse GHCR repository for #{entry.fetch('name')}" unless repo
    token_cache[repo] ||= ghcr_token(repo)
    temporary = Tempfile.new(['.wormswmd-bottle-', '.download'], cache_dir)
    begin
      temporary.close
      File.chmod(0o600, temporary.path)
      actual, = stream_bottle(uri, temporary.path, token_cache.fetch(repo))
      raise Error, "Bottle checksum mismatch for #{entry.fetch('name')}: #{actual}" unless actual == entry.fetch('bottle_sha256')
      File.link(temporary.path, out)
      out
    ensure
      temporary.close!
    end
  rescue Errno::EEXIST
    raise Error, "Bottle cache target appeared during download: #{out}"
  end

  def resolve_lock(root_formula, required_version, tag)
    raise Error, "Formula is not allowlisted: #{root_formula}" unless ALLOWED_FORMULAE.include?(root_formula)
    raise Error, "Invalid required version: #{required_version}" unless VERSION_RE.match?(required_version.to_s)
    raise Error, "Unsupported bottle tag: #{tag}" unless tag == DEFAULT_TAG
    queue = [root_formula]
    seen = {}
    entries = []
    until queue.empty?
      name = queue.shift
      next if seen[name]
      raise Error, "Resolved dependency is not allowlisted: #{name}" unless ALLOWED_FORMULAE.include?(name)
      json = fetch_json(name)
      version = json.dig('versions', 'stable')
      raise Error, "Formula #{name} has no stable version" unless version
      raise Error, "Expected #{root_formula} #{required_version}, found #{version}" if name == root_formula && version != required_version
      bottle = json.dig('bottle', 'stable', 'files', tag)
      raise Error, "Formula #{name} has no #{tag} bottle" unless bottle
      entries << {
        'name' => name, 'version' => version, 'bottle_tag' => tag,
        'bottle_sha256' => bottle.fetch('sha256'), 'bottle_url' => bottle.fetch('url'),
        'source_sha256' => json.dig('urls', 'stable', 'checksum').to_s,
        'ruby_source_sha256' => json.dig('ruby_source_checksum', 'sha256').to_s,
        'tap_git_head' => json.fetch('tap_git_head', '')
      }
      seen[name] = true
      Array(json['dependencies']).each { |dependency| queue << dependency unless seen[dependency] }
    end
    entries.each { |entry| validate_lock_entry!(entry) }
    entries
  rescue KeyError => error
    raise Error, "Incomplete formula metadata: #{error.message}"
  end

  def merge_refresh(original, refreshed, requested_formula)
    raise Error, "Refresh result omitted #{requested_formula}" unless refreshed.any? { |entry| entry['name'] == requested_formula }
    refreshed_by_name = refreshed.each_with_object({}) { |entry, memo| memo[entry.fetch('name')] = entry }
    candidate = original.map { |entry| refreshed_by_name.fetch(entry.fetch('name'), entry) }
    (refreshed_by_name.keys - original.map { |entry| entry.fetch('name') }).sort.each do |name|
      candidate << refreshed_by_name.fetch(name)
    end
    changes = candidate.each_with_object([]) do |entry, result|
      previous = original.find { |item| item['name'] == entry['name'] }
      result << [entry['name'], previous, entry] if previous != entry
    end
    [candidate, changes]
  end

  def python3
    candidates = ['/usr/bin/python3']
    begin
      xcrun, status = Open3.capture2e('xcrun', '--find', 'python3')
      candidates << xcrun.strip if status.success?
    rescue Errno::ENOENT
      nil
    end
    path_python = ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).map { |dir| File.join(dir, 'python3') }
                     .find { |path| File.executable?(path) }
    candidates << path_python if path_python
    candidates.compact.uniq.each do |candidate|
      next unless File.executable?(candidate)
      _output, status = Open3.capture2e(candidate, '-c', 'import sys; raise SystemExit(0 if sys.version_info >= (3, 9) else 1)')
      return candidate if status.success?
    end
    raise Error, 'Python 3.9 or newer is required; install or update Apple Command Line Tools.'
  end

  def inspect_bottle_archive!(source, entry, directory)
    regular_file!(source, 'Bottle archive', max_bytes: MAX_BOTTLE_BYTES)
    copy = File.join(directory, "#{entry.fetch('name').tr('@/', '__')}.tar.gz")
    raise Error, "Temporary bottle copy already exists: #{copy}" if File.exist?(copy) || File.symlink?(copy)
    run!(python3, INSPECTOR, '--profile', 'bottle', '--copy-to', copy,
         '--expected-sha256', entry.fetch('bottle_sha256'), '--quiet', source)
    listing = capture!('tar', '-tzf', copy)
    members = listing.lines.map { |line| line.chomp.sub(%r{\A\./}, '').sub(%r{/\z}, '') }.reject(&:empty?)
    formula = entry.fetch('name')
    cellar_versions = members.map do |member|
      parts = member.split('/')
      parts[1] if parts[0] == formula && parts.length >= 2
    end.compact.uniq
    version_pattern = /\A#{Regexp.escape(entry.fetch('version'))}(?:_[1-9][0-9]*)?\z/
    unless cellar_versions.length == 1 && version_pattern.match?(cellar_versions.first)
      raise Error, "Unexpected bottle version roots for #{formula}: #{cellar_versions.join(', ')}"
    end
    root = "#{formula}/#{cellar_versions.first}"
    unless !members.empty? && members.include?(root) &&
           members.all? { |member| member == formula || member == root || member.start_with?("#{root}/") }
      bad = members.find { |member| member != formula && member != root && !member.start_with?("#{root}/") }
      raise Error, "Unexpected bottle root path for #{entry.fetch('name')}: #{bad || '(empty)'}"
    end
    [copy, root]
  end

  def validate_bottle_metadata!(formula_root, entry)
    formula_path = File.join(
      formula_root, '.brew', "#{entry.fetch('name')}.rb"
    )
    formula = bounded_read(
      formula_path, 'Embedded Homebrew formula metadata', 1024 * 1024
    )
    formula.force_encoding(Encoding::UTF_8)
    unless formula.valid_encoding? &&
           !formula.match?(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/) &&
           formula.include?("sha256 \"#{entry.fetch('source_sha256')}\"")
      raise Error, "Embedded formula metadata mismatch for #{entry.fetch('name')}"
    end
    cellar_version = File.basename(formula_root)
    expected_version = entry.fetch('version')
    if cellar_version == expected_version
      if formula.lines.any? { |line| line.strip.match?(/\Arevision [1-9][0-9]*\z/) }
        raise Error, "Bottle revision metadata mismatch for #{entry.fetch('name')}"
      end
    else
      revision = cellar_version[/\A#{Regexp.escape(expected_version)}_([1-9][0-9]*)\z/, 1]
      unless revision && formula.lines.any? { |line| line.strip == "revision #{revision}" }
        raise Error, "Bottle revision metadata mismatch for #{entry.fetch('name')}"
      end
    end
  end

  def relocate_path(value, root)
    value.gsub('@@HOMEBREW_PREFIX@@', root)
         .gsub('@@HOMEBREW_CELLAR@@', File.join(root, 'Cellar'))
         .gsub('@@HOMEBREW_REPOSITORY@@', File.join(root, 'Homebrew'))
  end

  def macho_candidate?(path)
    File.file?(path) && (File.executable?(path) || File.extname(path) == '.dylib' || path.include?('.framework/Versions/'))
  end

  def macho_file?(path)
    capture!('file', '-b', path).include?('Mach-O')
  end

  def mach_o_id(path)
    capture!('otool', '-D', path).lines.map(&:strip)[1].to_s
  end

  def mach_o_deps(path)
    capture!('otool', '-L', path).lines.drop(1).map do |line|
      line.strip.sub(/\s+\(compatibility version .*\z/, '')
    end.reject(&:empty?)
  end

  def relocate_macho!(root)
    relocated = 0
    checked = []
    Find.find(File.join(root, 'Cellar')) do |path|
      next unless macho_candidate?(path) && macho_file?(path)
      checked << path
      current_id = mach_o_id(path)
      new_id = relocate_path(current_id, root)
      if !current_id.empty? && current_id != new_id
        run!('install_name_tool', '-id', new_id, path)
        relocated += 1
      end
      mach_o_deps(path).each do |dependency|
        relocated_dependency = relocate_path(dependency, root)
        next if dependency == relocated_dependency
        run!('install_name_tool', '-change', dependency, relocated_dependency, path)
        relocated += 1
      end
    end
    leftovers = checked.flat_map { |path| [mach_o_id(path), *mach_o_deps(path)] }
                       .grep(/@@HOMEBREW_(PREFIX|CELLAR|REPOSITORY)@@/)
    raise Error, "Unrelocated Homebrew placeholders remain:\n#{leftovers.uniq.join("\n")}" unless leftovers.empty?
    relocated
  end

  def marker_contents(path)
    expanded = File.expand_path(path)
    canonical = if File.exist?(expanded) && !File.symlink?(expanded)
                  File.realpath(expanded)
                else
                  File.join(File.realpath(File.dirname(expanded)), File.basename(expanded))
                end
    "format=1\noutput=#{canonical}\n"
  end

  def write_ownership_marker(directory, owned_path: directory)
    marker = File.join(directory, MARKER_NAME)
    raise Error, "Refusing existing ownership marker: #{marker}" if File.exist?(marker) || File.symlink?(marker)
    File.open(marker, 'wb', 0o600) do |file|
      file.write(marker_contents(owned_path))
      file.flush
      file.fsync
    end
  end

  def owned_output?(directory, expected_path: directory)
    marker = File.join(directory, MARKER_NAME)
    bounded_read(marker, 'Ownership marker', 4096) == marker_contents(expected_path)
  rescue Error, Errno::ENOENT
    false
  end

  def dangerous_output?(path, home, repo)
    return true if path == '/' || path == home || path == repo || path.start_with?("#{repo}/")
    return true if SYSTEM_EXACT.include?(path)
    SYSTEM_PREFIXES.any? { |prefix| path == prefix || path.start_with?("#{prefix}/") }
  end

  def validate_output_target(raw_path, home: Dir.home, repo: REPO_ROOT)
    raise Error, 'Output path contains a control character' if raw_path.to_s.match?(/[\x00-\x1f\x7f]/)
    expanded = File.expand_path(raw_path)
    raise Error, "Refusing dangerous output path: #{expanded}" if dangerous_output?(expanded, File.expand_path(home), File.expand_path(repo))
    raise Error, "Refusing symlink output: #{expanded}" if File.symlink?(expanded)
    parent = File.dirname(expanded)
    raise Error, "Output parent must already exist: #{parent}" unless File.directory?(parent)
    raise Error, "Output parent may not be a symlink: #{parent}" if File.symlink?(parent)
    canonical = File.join(File.realpath(parent), File.basename(expanded))
    canonical_home = File.exist?(home) ? File.realpath(home) : File.expand_path(home)
    canonical_repo = File.realpath(repo)
    raise Error, "Refusing dangerous output path: #{canonical}" if dangerous_output?(canonical, canonical_home, canonical_repo)
    return OutputTarget.new(path: canonical, state: :absent) unless File.exist?(canonical)
    stat = File.lstat(canonical)
    raise Error, "Output must be a non-symlink directory: #{canonical}" unless stat.directory? && !stat.symlink?
    return OutputTarget.new(path: canonical, state: :empty) if Dir.empty?(canonical)
    return OutputTarget.new(path: canonical, state: :owned) if owned_output?(canonical)
    raise Error, "Refusing nonempty output without a valid ownership marker: #{canonical}"
  rescue Errno::ENOENT => error
    raise Error, "Could not validate output path: #{error.message}"
  end

  def publish_staging!(staging, target, replace_owned: false)
    case target.state
    when :absent
      File.rename(staging, target.path)
    when :empty
      moved = []
      begin
        Dir.children(staging).each do |entry|
          File.rename(File.join(staging, entry), File.join(target.path, entry))
          moved << entry
        end
        Dir.rmdir(staging)
      rescue StandardError
        moved.reverse_each do |entry|
          destination = File.join(target.path, entry)
          File.rename(destination, File.join(staging, entry)) if File.exist?(destination) || File.symlink?(destination)
        end
        raise
      end
    when :owned
      raise Error, 'Owned output exists; pass --replace-owned-output after reviewing the exact path.' unless replace_owned
      raise Error, 'Output ownership changed before replacement' unless owned_output?(target.path)
      backup = "#{target.path}.previous-#{Process.pid}"
      raise Error, "Replacement backup path already exists: #{backup}" if File.exist?(backup) || File.symlink?(backup)
      File.rename(target.path, backup)
      begin
        File.rename(staging, target.path)
      rescue StandardError
        File.rename(backup, target.path) unless File.exist?(target.path)
        raise
      end
      unless owned_output?(backup, expected_path: target.path)
        raise Error, 'Previous output lost its ownership marker during replacement'
      end
      FileUtils.remove_entry_secure(backup)
    else
      raise Error, "Unknown output state: #{target.state}"
    end
  end

  def clean_owned_output!(target)
    raise Error, 'Only a marker-owned output may be cleaned' unless target.state == :owned && owned_output?(target.path)
    quarantine = "#{target.path}.clean-#{Process.pid}"
    raise Error, "Cleanup staging path already exists: #{quarantine}" if File.exist?(quarantine) || File.symlink?(quarantine)
    puts "Cleaning marker-owned output: #{target.path}"
    File.rename(target.path, quarantine)
    FileUtils.remove_entry_secure(quarantine)
  end

  def install_entries!(entries, staging, cache)
    cellar = File.join(staging, 'Cellar')
    opt = File.join(staging, 'opt')
    FileUtils.mkdir_p([cellar, opt], mode: 0o700)
    token_cache = {}
    archive_directory = Dir.mktmpdir('.archives-', staging)
    entries.each do |entry|
      puts "Fetching #{entry.fetch('name')} #{entry.fetch('version')} (#{entry.fetch('bottle_tag')})"
      cached = download_blob(entry, cache, token_cache)
      archive, root = inspect_bottle_archive!(cached, entry, archive_directory)
      run!('tar', '-xzf', archive, '-C', cellar)
      formula_root = File.join(cellar, root)
      unless File.directory?(formula_root) && !File.symlink?(formula_root)
        raise Error, "Bottle root was not extracted as a directory: #{root}"
      end
      unless File.realpath(formula_root).start_with?("#{File.realpath(cellar)}/")
        raise Error, "Bottle root escaped Cellar: #{root}"
      end
      validate_bottle_metadata!(formula_root, entry)
      File.symlink(File.join('..', 'Cellar', root), File.join(opt, entry.fetch('name')))
    end
    FileUtils.remove_entry_secure(archive_directory)
  end

  def validate_qt!(root, entry)
    qt_prefix = File.join(root, 'opt', entry.fetch('name'))
    qt_core = File.join(qt_prefix, 'lib', 'QtCore.framework', 'Versions', '5', 'QtCore')
    regular_file!(qt_core, 'QtCore framework binary')
    architectures = capture!('lipo', '-archs', qt_core).split
    raise Error, "QtCore is missing x86_64 slice: #{architectures.join(' ')}" unless architectures.include?('x86_64')
    [qt_prefix, entry.fetch('version')]
  end

  def build_prefix!(entries, target, cache, replace_owned: false)
    parent = File.dirname(target.path)
    staging = Dir.mktmpdir(".#{File.basename(target.path)}.stage-", parent)
    begin
      install_entries!(entries, staging, cache)
      relocated = relocate_macho!(staging)
      root_entry = entries.find { |entry| entry.fetch('name') == DEFAULT_FORMULA }
      raise Error, "Bottle lock omitted #{DEFAULT_FORMULA}" unless root_entry
      _qt_prefix, qt_version = validate_qt!(staging, root_entry)
      write_ownership_marker(staging, owned_path: target.path)
      current_target = validate_output_target(target.path)
      unless current_target.path == target.path && current_target.state == target.state
        raise Error, "Output state changed during staging: #{target.path}"
      end
      puts "Publishing staged output: #{target.path}"
      publish_staging!(staging, target, replace_owned: replace_owned)
      staging = nil
      puts "Relocated Mach-O references: #{relocated}"
      puts "Qt prefix: #{File.join(target.path, 'opt', root_entry.fetch('name'))}"
      puts "Qt version: #{qt_version}"
      puts "Bottle entries: #{entries.length}"
    ensure
      FileUtils.remove_entry_secure(staging) if staging && File.exist?(staging)
    end
  end

  def parser(options)
    OptionParser.new do |opts|
      opts.banner = 'Usage: fetch_qt_homebrew_bottles.rb --output DIR [--lock FILE]'
      opts.on('--formula NAME', 'Root formula to resolve (default: qt@5)') { |value| options[:formula] = value }
      opts.on('--version VERSION', 'Required root or refreshed formula version') { |value| options[:version] = value }
      opts.on('--tag TAG', 'Homebrew bottle tag (default: sonoma)') { |value| options[:tag] = value }
      opts.on('--output DIR', 'Isolated Homebrew-like output prefix') { |value| options[:output] = value }
      opts.on('--cache DIR', 'Bottle download cache directory') { |value| options[:cache] = value }
      opts.on('--write-lock FILE', 'Write a resolved or refreshed candidate lock') { |value| options[:write_lock] = value }
      opts.on('--lock FILE', 'Reviewed bottle lock (default: packaging lock)') { |value| options[:lock] = value }
      opts.on('--refresh-formula NAME', 'Refresh only NAME and its dependency rows') { |value| options[:refresh_formula] = value }
      opts.on('--replace-owned-output', 'Replace the exact marker-owned output') { options[:replace_owned] = true }
      opts.on('--clean-owned-output', 'Remove the exact marker-owned output and exit') { options[:clean_owned] = true }
      opts.on('-h', '--help', 'Show this help') { options[:help] = true }
    end
  end

  def main(argv)
    options = {
      formula: DEFAULT_FORMULA, tag: DEFAULT_TAG,
      cache: File.join(Dir.tmpdir, 'wormswmd-homebrew-bottles'),
      lock: DEFAULT_LOCK, replace_owned: false, clean_owned: false
    }
    option_parser = parser(options)
    option_parser.parse!(argv)
    if options[:help]
      puts option_parser
      return 0
    end
    raise Error, "Unexpected arguments: #{argv.join(' ')}" unless argv.empty?
    if options[:write_lock] && !options[:refresh_formula]
      raise Error, '--write-lock is available only with --refresh-formula'
    end
    if options[:refresh_formula]
      if options[:output] || options[:replace_owned] || options[:clean_owned]
        raise Error, '--refresh-formula cannot be combined with output mutation options'
      end
      if options[:version].to_s.empty? || options[:write_lock].to_s.empty?
        raise Error, '--refresh-formula requires --version and --write-lock'
      end
      original = read_lock(options.fetch(:lock))
      refreshed = resolve_lock(options.fetch(:refresh_formula), options.fetch(:version), options.fetch(:tag))
      candidate, changes = merge_refresh(original, refreshed, options.fetch(:refresh_formula))
      validate_entries!(candidate)
      if File.expand_path(options.fetch(:write_lock)) == File.expand_path(options.fetch(:lock))
        raise Error, 'Candidate lock must differ from the reviewed input path'
      end
      write_lock(options.fetch(:write_lock), candidate)
      if changes.empty?
        puts 'No lock row changes.'
      else
        changes.each do |name, before, after|
          fields = LOCK_HEADER.select { |field| before.nil? || before[field] != after[field] }
          puts "Changed #{name}: #{fields.join(', ')}"
        end
      end
      puts "Candidate lock: #{File.expand_path(options.fetch(:write_lock))}"
      return 0
    end
    unless options[:formula] == DEFAULT_FORMULA
      raise Error, "Reviewed packaging root is fixed to #{DEFAULT_FORMULA}"
    end
    unless options[:tag] == DEFAULT_TAG
      raise Error, "Reviewed packaging bottle tag is fixed to #{DEFAULT_TAG}"
    end
    raise Error, '--output is required' if options[:output].to_s.empty?
    target = validate_output_target(options.fetch(:output))
    if options[:clean_owned]
      raise Error, '--clean-owned-output cannot be combined with --replace-owned-output' if options[:replace_owned]
      clean_owned_output!(target)
      return 0
    end
    if options[:replace_owned] && target.state != :owned
      raise Error, '--replace-owned-output requires the exact marker-owned output path'
    end
    entries = read_lock(options.fetch(:lock))
    root_entry = entries.find { |entry| entry.fetch('name') == options.fetch(:formula) }
    raise Error, "Lock does not contain root formula #{options.fetch(:formula)}" unless root_entry
    if options[:version] && root_entry.fetch('version') != options[:version]
      raise Error, "Expected #{options.fetch(:formula)} #{options[:version]}, found #{root_entry.fetch('version')}"
    end
    cache = safe_cache_directory(options.fetch(:cache))
    puts "Output target: #{target.path} (#{target.state})"
    build_prefix!(entries, target, cache, replace_owned: options[:replace_owned])
    0
  rescue Error, OptionParser::ParseError, IOError, SocketError, SystemCallError,
         Timeout::Error, OpenSSL::SSL::SSLError => error
    warn "ERROR: #{error.message}"
    1
  end
end

exit WormsBottleFetcher.main(ARGV) if $PROGRAM_NAME == __FILE__
