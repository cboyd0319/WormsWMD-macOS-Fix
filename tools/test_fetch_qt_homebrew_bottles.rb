#!/usr/bin/env ruby
# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'rubygems/package'
require 'minitest/autorun'
require 'open3'
require 'zlib'
require 'tmpdir'

require_relative 'fetch_qt_homebrew_bottles'

class FetchQtHomebrewBottlesTest < Minitest::Test
  Fetcher = WormsBottleFetcher
  ROOT = File.expand_path('..', __dir__)
  LOCK = File.join(ROOT, 'packaging', 'qt-homebrew-lock.tsv')

  def setup
    @tmp = Dir.mktmpdir('wormswmd-bottle-test-')
  end

  def teardown
    FileUtils.remove_entry_secure(@tmp) if File.exist?(@tmp)
  end

  def entry(name = 'qt@5', version = '5.15.19', digest = 'a' * 64)
    {
      'name' => name,
      'version' => version,
      'bottle_tag' => 'sonoma',
      'bottle_sha256' => digest,
      'bottle_url' => "https://ghcr.io/v2/homebrew/core/#{name.tr('@', '/')}/blobs/sha256:#{digest}",
      'source_sha256' => 'b' * 64,
      'ruby_source_sha256' => 'c' * 64,
      'tap_git_head' => 'd' * 40
    }
  end

  def write_lock(path, entries, header: Fetcher::LOCK_HEADER)
    File.open(path, 'wb', 0o600) do |file|
      file.puts('# WormsWMD Homebrew bottle lock v1')
      file.puts(header.join("\t"))
      entries.each { |item| file.puts(header.map { |key| item.fetch(key, '') }.join("\t")) }
    end
  end

  def write_archive(path, files, symlinks: {})
    directories = files.keys.flat_map do |name|
      parts = name.split('/')[0...-1]
      (1..parts.length).map { |length| parts.first(length).join('/') }
    end.uniq.sort_by { |name| [name.count('/'), name] }
    Zlib::GzipWriter.open(path) do |gzip|
      Gem::Package::TarWriter.new(gzip) do |tar|
        directories.each { |directory| tar.mkdir(directory, 0o755) }
        files.each do |name, value|
          data, mode = value.is_a?(Array) ? value : [value, 0o644]
          tar.add_file_simple(name, mode, data.bytesize) { |file| file.write(data) }
        end
        symlinks.each { |name, target| tar.add_symlink(name, target, 0o777) }
      end
    end
  end

  def formula_metadata(item)
    "url \"https://example.invalid/#{item.fetch('version')}.tar.gz\"\n" \
      "sha256 \"#{item.fetch('source_sha256')}\"\n"
  end

  def complete_fixture
    cache = File.join(@tmp, 'cache')
    fake_bin = File.join(@tmp, 'bin')
    lock = File.join(@tmp, 'complete.tsv')
    qmake_marker = File.join(@tmp, 'qmake-ran')
    FileUtils.mkdir_p([cache, fake_bin])
    entries = Fetcher.read_lock(LOCK).map do |item|
      name = item.fetch('name')
      version = item.fetch('version')
      root = "#{name}/#{version}"
      files = { "#{root}/.brew/#{name}.rb" => formula_metadata(item) }
      if name == 'qt@5'
        files["#{root}/lib/QtCore.framework/Versions/5/QtCore"] = ["fake Mach-O\n", 0o755]
        files["#{root}/bin/qmake"] = ["#!/bin/sh\nprintf ran > \"$QMAKE_MARKER\"\n", 0o755]
      end
      archive = File.join(@tmp, "#{name.tr('@/', '__')}.tar.gz")
      write_archive(archive, files)
      digest = Digest::SHA256.file(archive).hexdigest
      changed = item.merge(
        'bottle_sha256' => digest,
        'bottle_url' => "https://ghcr.io/v2/homebrew/core/#{name.tr('@', '/')}/blobs/sha256:#{digest}"
      )
      FileUtils.cp(archive, File.join(cache, Fetcher.cache_filename(changed)))
      changed
    end
    write_lock(lock, entries)
    File.write(File.join(fake_bin, 'file'), "#!/bin/sh\nprintf 'ASCII text\\n'\n")
    File.write(File.join(fake_bin, 'lipo'), <<~SH)
      #!/bin/sh
      [ "${FAKE_LIPO_FAIL:-0}" = 1 ] && exit 1
      printf 'x86_64\n'
    SH
    FileUtils.chmod(0o755, [File.join(fake_bin, 'file'), File.join(fake_bin, 'lipo')])
    [lock, cache, fake_bin, qmake_marker]
  end

  def test_reads_current_authoritative_lock
    entries = Fetcher.read_lock(LOCK)

    assert_equal(Fetcher::ALLOWED_FORMULAE.sort, entries.map { |item| item.fetch('name') }.sort)
    assert_equal('5.15.19', entries.find { |item| item.fetch('name') == 'qt@5' }.fetch('version'))
  end

  def test_rejects_oversized_excess_malformed_duplicate_and_unallowlisted_locks
    path = File.join(@tmp, 'lock.tsv')
    cases = []
    cases << proc { File.binwrite(path, 'x' * (Fetcher::MAX_LOCK_BYTES + 1)) }
    cases << proc { write_lock(path, Array.new(Fetcher::MAX_LOCK_ROWS + 1) { |i| entry("fake#{i}") }) }
    cases << proc { File.binwrite(path, "name\tversion\nqt@5\t5.15.19\n") }
    cases << proc { write_lock(path, [entry, entry]) }
    cases << proc { write_lock(path, [entry('evil')]) }

    cases.each do |prepare|
      prepare.call
      assert_raises(Fetcher::Error) { Fetcher.read_lock(path, require_complete: false) }
    end
  end

  def test_rejects_invalid_version_tag_hash_commit_and_url_contracts
    mutations = {
      'version' => '../5.15.19',
      'bottle_tag' => 'Sonoma!',
      'bottle_sha256' => 'A' * 64,
      'source_sha256' => 'short',
      'ruby_source_sha256' => 'z' * 64,
      'tap_git_head' => 'e' * 39,
      'bottle_url' => 'file:///tmp/bottle.tar.gz'
    }

    mutations.each do |field, value|
      path = File.join(@tmp, "#{field}.tsv")
      changed = entry.merge(field => value)
      write_lock(path, [changed])
      assert_raises(Fetcher::Error, field) do
        Fetcher.read_lock(path, require_complete: false)
      end
    end

    %w[
      http://ghcr.io/v2/homebrew/core/qt/5/blobs/sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
      https://example.invalid/v2/homebrew/core/qt/5/blobs/sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
      https://ghcr.io/v2/homebrew/core/other/blobs/sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    ].each do |url|
      path = File.join(@tmp, 'bad-url.tsv')
      write_lock(path, [entry.merge('bottle_url' => url)])
      assert_raises(Fetcher::Error) { Fetcher.read_lock(path, require_complete: false) }
    end
  end

  def test_redirect_policy_rejects_downgrade_and_unreviewed_hosts_and_drops_auth_cross_origin
    origin = URI('https://ghcr.io/v2/homebrew/core/qt/5/blobs/sha256:' + ('a' * 64))

    same, same_auth = Fetcher.redirect_target(origin, '/same', origin)
    assert_equal('ghcr.io', same.host)
    assert(same_auth)

    cross, cross_auth = Fetcher.redirect_target(
      origin,
      'https://pkg-containers.githubusercontent.com/object',
      origin
    )
    assert_equal('pkg-containers.githubusercontent.com', cross.host)
    refute(cross_auth)

    assert_raises(Fetcher::Error) { Fetcher.redirect_target(origin, 'http://ghcr.io/object', origin) }
    assert_raises(Fetcher::Error) do
      Fetcher.redirect_target(origin, 'https://attacker.invalid/object', origin)
    end
  end

  def test_streaming_redirect_does_not_forward_bearer_to_storage_origin
    initial = URI('https://ghcr.io/v2/homebrew/core/qt/5/blobs/sha256:' + ('a' * 64))
    redirect = Net::HTTPFound.new('1.1', '302', 'Found')
    redirect['location'] = 'https://pkg-containers.githubusercontent.com/object'
    success = Net::HTTPOK.new('1.1', '200', 'OK')
    success['content-length'] = '4'
    success.define_singleton_method(:read_body) { |&block| block.call('data') }
    responses = [redirect, success]
    calls = []
    fake_http = lambda do |uri, headers = {}, &block|
      calls << [uri, headers]
      block.call(responses.shift)
    end
    destination = File.join(@tmp, 'download')

    digest, bytes = Fetcher.stub(:http_response, fake_http) do
      Fetcher.stream_bottle(initial, destination, 'secret-token')
    end

    assert_equal(Digest::SHA256.hexdigest('data'), digest)
    assert_equal(4, bytes)
    assert_equal('Bearer secret-token', calls.fetch(0).fetch(1)['Authorization'])
    refute(calls.fetch(1).fetch(1).key?('Authorization'))
  end

  def test_streaming_download_enforces_redirect_limit
    initial = URI('https://ghcr.io/v2/homebrew/core/qt/5/blobs/sha256:' + ('a' * 64))
    redirects = Array.new(Fetcher::MAX_REDIRECTS + 1) do |index|
      response = Net::HTTPFound.new('1.1', '302', 'Found')
      response['location'] = "/redirect-#{index}"
      response
    end
    fake_http = lambda do |_uri, _headers = {}, &block|
      block.call(redirects.shift)
    end

    assert_raises(Fetcher::Error) do
      Fetcher.stub(:http_response, fake_http) do
        Fetcher.stream_bottle(initial, File.join(@tmp, 'too-many'), 'token')
      end
    end
  end

  def test_output_policy_rejects_dangerous_links_and_foreign_nonempty_targets
    repo = ROOT
    home = File.join(@tmp, 'home')
    FileUtils.mkdir_p(home)
    foreign = File.join(@tmp, 'foreign')
    FileUtils.mkdir_p(foreign)
    File.write(File.join(foreign, 'victim'), "keep\n")
    linked = File.join(@tmp, 'linked')
    File.symlink(foreign, linked)

    ['/', home, repo, '/System', '/Library/wormswmd-test', linked, foreign].each do |path|
      assert_raises(Fetcher::Error, path) do
        Fetcher.validate_output_target(path, home: home, repo: repo)
      end
    end

    empty = File.join(@tmp, 'empty')
    FileUtils.mkdir_p(empty)
    assert_equal(:empty, Fetcher.validate_output_target(empty, home: home, repo: repo).state)
    assert_equal(:absent, Fetcher.validate_output_target(File.join(@tmp, 'new'), home: home, repo: repo).state)
    assert_equal("keep\n", File.read(File.join(foreign, 'victim')))
  end

  def test_ownership_marker_is_bound_to_exact_output_path
    output = File.join(@tmp, 'owned')
    FileUtils.mkdir_p(output)
    Fetcher.write_ownership_marker(output)

    assert_equal(:owned, Fetcher.validate_output_target(output, home: File.join(@tmp, 'home'), repo: ROOT).state)

    copied = File.join(@tmp, 'copied')
    FileUtils.cp_r(output, copied)
    assert_raises(Fetcher::Error) do
      Fetcher.validate_output_target(copied, home: File.join(@tmp, 'home'), repo: ROOT)
    end
  end

  def test_refresh_merge_changes_only_requested_closure
    original = [entry('qt@5'), entry('freetype', '2.14.3'), entry('glib', '2.88.1')]
    refreshed = [entry('freetype', '2.15.0', 'e' * 64)]

    candidate, changes = Fetcher.merge_refresh(original, refreshed, 'freetype')

    assert_equal('2.15.0', candidate.find { |item| item['name'] == 'freetype' }['version'])
    assert_equal(original.find { |item| item['name'] == 'glib' }, candidate.find { |item| item['name'] == 'glib' })
    assert_equal(['freetype'], changes.map(&:first))
  end

  def test_refresh_cli_writes_a_separate_candidate_and_reports_only_changed_rows
    original = Fetcher.read_lock(LOCK)
    current = original.find { |item| item.fetch('name') == 'freetype' }
    digest = 'e' * 64
    refreshed = current.merge(
      'version' => '2.15.0',
      'bottle_sha256' => digest,
      'bottle_url' => "https://ghcr.io/v2/homebrew/core/freetype/blobs/sha256:#{digest}"
    )
    candidate_path = File.join(@tmp, 'candidate.tsv')
    result = nil

    stdout, stderr = capture_io do
      Fetcher.stub(:resolve_lock, [refreshed]) do
        result = Fetcher.main(
          [
            '--lock', LOCK,
            '--refresh-formula', 'freetype',
            '--version', '2.15.0',
            '--write-lock', candidate_path
          ]
        )
      end
    end

    assert_equal(0, result, stderr)
    candidate = Fetcher.read_lock(candidate_path)
    assert_equal('2.15.0', candidate.find { |item| item['name'] == 'freetype' }['version'])
    assert_equal(
      original.find { |item| item['name'] == 'glib' },
      candidate.find { |item| item['name'] == 'glib' }
    )
    assert_includes(stdout, 'Changed freetype: version, bottle_sha256, bottle_url')
    assert_includes(stdout, "Candidate lock: #{candidate_path}")
    refute_includes(stdout, 'Changed glib:')
  end

  def test_source_never_executes_extracted_qmake
    source = File.read(File.join(ROOT, 'tools', 'fetch_qt_homebrew_bottles.rb'))

    refute_match(/capture!\([^\n]*qmake/, source)
    refute_match(/system\([^\n]*qmake/, source)
  end

  def test_standard_build_refuses_unreviewed_root_or_tag_before_output_mutation
    output = File.join(@tmp, 'unreviewed-output')

    refute_equal(
      0,
      Fetcher.main(['--formula', 'freetype', '--output', output])
    )
    refute_equal(
      0,
      Fetcher.main(['--tag', 'ventura', '--output', output])
    )
    refute(File.exist?(output))
  end

  def test_archive_inspection_enforces_digest_root_and_safe_members
    archive = File.join(@tmp, 'valid.tar.gz')
    valid = entry
    root = "#{valid['name']}/#{valid['version']}"
    write_archive(archive, "#{root}/.brew/qt@5.rb" => formula_metadata(valid))
    digest = Digest::SHA256.file(archive).hexdigest
    valid = valid.merge(
      'bottle_sha256' => digest,
      'bottle_url' => "https://ghcr.io/v2/homebrew/core/qt/5/blobs/sha256:#{digest}"
    )
    copy_dir = File.join(@tmp, 'copies')
    FileUtils.mkdir_p(copy_dir)

    copy, actual_root = Fetcher.inspect_bottle_archive!(archive, valid, copy_dir)
    assert(File.file?(copy))
    assert_equal(root, actual_root)

    wrong = File.join(@tmp, 'wrong.tar.gz')
    write_archive(wrong, 'other/1.0/file' => 'x')
    wrong_digest = Digest::SHA256.file(wrong).hexdigest
    wrong_entry = valid.merge(
      'bottle_sha256' => wrong_digest,
      'bottle_url' => "https://ghcr.io/v2/homebrew/core/qt/5/blobs/sha256:#{wrong_digest}"
    )
    assert_raises(Fetcher::Error) do
      Fetcher.inspect_bottle_archive!(wrong, wrong_entry, File.join(@tmp, 'wrong-copy').tap { |dir| FileUtils.mkdir_p(dir) })
    end

    unsafe = File.join(@tmp, 'unsafe.tar.gz')
    write_archive(
      unsafe,
      { "#{root}/.brew/qt@5.rb" => formula_metadata(valid) },
      symlinks: { "#{root}/escape" => '../../../outside' }
    )
    unsafe_digest = Digest::SHA256.file(unsafe).hexdigest
    unsafe_entry = valid.merge(
      'bottle_sha256' => unsafe_digest,
      'bottle_url' => "https://ghcr.io/v2/homebrew/core/qt/5/blobs/sha256:#{unsafe_digest}"
    )
    assert_raises(Fetcher::Error) do
      Fetcher.inspect_bottle_archive!(unsafe, unsafe_entry, File.join(@tmp, 'unsafe-copy').tap { |dir| FileUtils.mkdir_p(dir) })
    end
  end

  def test_revisioned_cellar_root_requires_matching_embedded_formula_revision
    item = entry('libtiff', '4.7.1')
    formula_root = File.join(@tmp, 'libtiff', '4.7.1_1')
    FileUtils.mkdir_p(File.join(formula_root, '.brew'))
    File.write(
      File.join(formula_root, '.brew', 'libtiff.rb'),
      formula_metadata(item) + "revision 1\n"
    )

    Fetcher.validate_bottle_metadata!(formula_root, item)

    File.write(
      File.join(formula_root, '.brew', 'libtiff.rb'),
      formula_metadata(item) + "revision 2\n"
    )
    assert_raises(Fetcher::Error) do
      Fetcher.validate_bottle_metadata!(formula_root, item)
    end
  end

  def test_staged_build_never_runs_qmake_preserves_failed_output_and_requires_owned_replace
    lock, cache, fake_bin, qmake_marker = complete_fixture
    output = File.join(@tmp, 'prefix')
    FileUtils.mkdir_p(output)
    empty_output_inode = File.stat(output).ino
    environment = {
      'PATH' => "#{fake_bin}:#{ENV.fetch('PATH')}",
      'QMAKE_MARKER' => qmake_marker
    }
    command = [File.join(ROOT, 'tools', 'fetch_qt_homebrew_bottles.rb'), '--lock', lock,
               '--output', output, '--cache', cache]

    stdout, stderr, status = Open3.capture3(environment, *command)
    assert(status.success?, "#{stdout}\n#{stderr}")
    assert_equal(empty_output_inode, File.stat(output).ino, 'selected empty output directory was replaced')
    assert_includes(stdout, "Publishing staged output: #{File.realpath(output)}")
    refute(File.exist?(qmake_marker), 'extracted qmake was executed')
    assert(File.file?(File.join(output, Fetcher::MARKER_NAME)))

    sentinel = File.join(output, 'sentinel')
    File.write(sentinel, "preserve\n")
    _stdout, _stderr, refused = Open3.capture3(environment, *command)
    refute(refused.success?)
    assert_equal("preserve\n", File.read(sentinel))

    _stdout, _stderr, failed = Open3.capture3(
      environment.merge('FAKE_LIPO_FAIL' => '1'), *command, '--replace-owned-output'
    )
    refute(failed.success?)
    assert_equal("preserve\n", File.read(sentinel))

    stdout, stderr, replaced = Open3.capture3(environment, *command, '--replace-owned-output')
    assert(replaced.success?, "#{stdout}\n#{stderr}")
    refute(File.exist?(sentinel))
    refute(File.exist?(qmake_marker))

    _stdout, _stderr, cleaned = Open3.capture3(
      environment, File.join(ROOT, 'tools', 'fetch_qt_homebrew_bottles.rb'),
      '--output', output, '--clean-owned-output'
    )
    assert(cleaned.success?)
    refute(File.exist?(output))
  end

  def test_cached_digest_mismatch_fails_without_network_or_output_mutation
    lock, cache, fake_bin, = complete_fixture
    entries = Fetcher.read_lock(lock)
    cached = File.join(cache, Fetcher.cache_filename(entries.first))
    File.open(cached, 'ab') { |file| file.write('tampered') }
    output = File.join(@tmp, 'digest-output')

    _stdout, stderr, status = Open3.capture3(
      { 'PATH' => "#{fake_bin}:#{ENV.fetch('PATH')}" },
      File.join(ROOT, 'tools', 'fetch_qt_homebrew_bottles.rb'),
      '--lock', lock, '--output', output, '--cache', cache
    )

    refute(status.success?)
    assert_match(/checksum mismatch/, stderr)
    refute(File.exist?(output))
  end
end
