#!/usr/bin/env ruby
# frozen_string_literal: true

# Fetches a checksum-pinned Homebrew bottle closure into an isolated prefix.
# This is a maintainer supply-chain helper for building the bundled Qt archive.

require 'fileutils'
require 'find'
require 'json'
require 'open3'
require 'optparse'
require 'shellwords'
require 'tmpdir'
require 'uri'

DEFAULT_FORMULA = 'qt@5'
DEFAULT_TAG = 'sonoma'
LOCK_HEADER = %w[name version bottle_tag bottle_sha256 bottle_url source_sha256 ruby_source_sha256 tap_git_head].freeze

options = {
  formula: DEFAULT_FORMULA,
  tag: DEFAULT_TAG,
  cache: File.join(Dir.tmpdir, 'wormswmd-homebrew-bottles')
}

parser = OptionParser.new do |opts|
  opts.banner = 'Usage: fetch_qt_homebrew_bottles.rb --output DIR [--write-lock FILE] [--lock FILE]'
  opts.on('--formula NAME', 'Root formula to resolve (default: qt@5)') { |value| options[:formula] = value }
  opts.on('--version VERSION', 'Required root formula version') { |value| options[:version] = value }
  opts.on('--tag TAG', 'Homebrew bottle tag to use (default: sonoma)') { |value| options[:tag] = value }
  opts.on('--output DIR', 'Isolated Homebrew-like output prefix') { |value| options[:output] = value }
  opts.on('--cache DIR', 'Bottle download cache directory') { |value| options[:cache] = value }
  opts.on('--write-lock FILE', 'Write resolved bottle lock/provenance TSV') { |value| options[:write_lock] = value }
  opts.on('--lock FILE', 'Use an existing bottle lock/provenance TSV') { |value| options[:lock] = value }
end

parser.parse!(ARGV)

abort parser.to_s if options[:output].to_s.empty?
abort 'Use either --lock or --write-lock, not both.' if options[:lock] && options[:write_lock]

def run!(*cmd)
  system(*cmd) || abort("Command failed: #{cmd.shelljoin}")
end

def capture!(*cmd)
  output, status = Open3.capture2e(*cmd)
  abort("Command failed: #{cmd.shelljoin}\n#{output}") unless status.success?
  output
end

def fetch_json(formula)
  encoded = URI.encode_www_form_component(formula)
  JSON.parse(capture!('curl', '-fsSL', "https://formulae.brew.sh/api/formula/#{encoded}.json"))
end

def ghcr_token(repo)
  json = capture!('curl', '-fsSL', "https://ghcr.io/token?service=ghcr.io&scope=repository:#{repo}:pull")
  JSON.parse(json).fetch('token')
end

def download_blob(entry, cache_dir, token_cache)
  FileUtils.mkdir_p(cache_dir)
  bottle_url = entry.fetch('bottle_url')
  sha = entry.fetch('bottle_sha256')
  out = File.join(cache_dir, "#{entry.fetch('name').tr('/', '_')}--#{entry.fetch('version')}.#{entry.fetch('bottle_tag')}.bottle.tar.gz")

  unless File.exist?(out)
    uri = URI(bottle_url)
    if uri.host == 'ghcr.io'
      repo = uri.path[%r{\A/v2/(.*)/blobs/sha256:}, 1] || abort("Cannot parse GHCR repo from #{bottle_url}")
      token_cache[repo] ||= ghcr_token(repo)
      run!('curl', '-L', '--fail', '--retry', '3', '--max-time', '300',
           '-H', "Authorization: Bearer #{token_cache[repo]}", '-o', out, bottle_url)
    else
      run!('curl', '-L', '--fail', '--retry', '3', '--max-time', '300', '-o', out, bottle_url)
    end
  end

  actual = capture!('shasum', '-a', '256', out).split.first
  abort("Bottle checksum mismatch for #{entry.fetch('name')}: #{actual} != #{sha}") unless actual == sha

  out
end

def resolve_lock(root_formula, required_version, tag)
  queue = [root_formula]
  seen = {}
  entries = []

  until queue.empty?
    name = queue.shift
    next if seen[name]

    json = fetch_json(name)
    version = json.dig('versions', 'stable') || abort("Formula #{name} has no stable version")
    if name == root_formula && required_version && version != required_version
      abort("Expected #{root_formula} #{required_version}, found #{version}")
    end

    bottle = json.dig('bottle', 'stable', 'files', tag) || abort("Formula #{name} has no #{tag.inspect} bottle")
    entries << {
      'name' => name,
      'version' => version,
      'bottle_tag' => tag,
      'bottle_sha256' => bottle.fetch('sha256'),
      'bottle_url' => bottle.fetch('url'),
      'source_sha256' => json.dig('urls', 'stable', 'checksum').to_s,
      'ruby_source_sha256' => json.dig('ruby_source_checksum', 'sha256').to_s,
      'tap_git_head' => json.fetch('tap_git_head', '')
    }

    seen[name] = true
    Array(json['dependencies']).each { |dep| queue << dep unless seen[dep] }
  end

  entries
end

def write_lock(path, entries)
  FileUtils.mkdir_p(File.dirname(path))
  File.open(path, 'w') do |file|
    file.puts '# WormsWMD Homebrew bottle lock v1'
    file.puts "# generated_utc\t#{Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')}"
    file.puts LOCK_HEADER.join("\t")
    entries.each do |entry|
      file.puts LOCK_HEADER.map { |key| entry.fetch(key, '') }.join("\t")
    end
  end
end

def read_lock(path)
  lines = File.readlines(path, chomp: true).reject { |line| line.empty? || line.start_with?('#') }
  header = lines.shift&.split("\t")
  abort("Invalid lock header in #{path}") unless header == LOCK_HEADER

  lines.map do |line|
    values = line.split("\t", -1)
    abort("Invalid lock row in #{path}: #{line}") unless values.length == LOCK_HEADER.length
    LOCK_HEADER.zip(values).to_h
  end
end

def relocate_path(value, root)
  value.gsub('@@HOMEBREW_PREFIX@@', root)
       .gsub('@@HOMEBREW_CELLAR@@', File.join(root, 'Cellar'))
       .gsub('@@HOMEBREW_REPOSITORY@@', File.join(root, 'Homebrew'))
end

def macho_candidate?(path)
  return false unless File.file?(path)
  return true if File.executable?(path)
  return true if File.extname(path) == '.dylib'
  return true if path.include?('.framework/Versions/')

  false
end

def macho_file?(path)
  capture!('file', '-b', path).include?('Mach-O')
end

def mach_o_id(path)
  lines = capture!('otool', '-D', path).lines.map(&:strip)
  lines[1].to_s
rescue SystemExit
  ''
end

def mach_o_deps(path)
  capture!('otool', '-L', path).lines.drop(1).map do |line|
    line.strip.sub(/\s+\(compatibility version .*$/, '')
  end.reject(&:empty?)
rescue SystemExit
  []
end

def relocate_macho!(root)
  relocated = 0
  checked = []

  Find.find(File.join(root, 'Cellar')) do |path|
    next unless macho_candidate?(path)
    next unless macho_file?(path)

    checked << path
    current_id = mach_o_id(path)
    new_id = relocate_path(current_id, root)
    if !current_id.empty? && current_id != new_id
      run!('install_name_tool', '-id', new_id, path)
      relocated += 1
    end

    mach_o_deps(path).each do |dep|
      new_dep = relocate_path(dep, root)
      next if dep == new_dep

      run!('install_name_tool', '-change', dep, new_dep, path)
      relocated += 1
    end
  end

  leftovers = checked.flat_map { |path| [mach_o_id(path), *mach_o_deps(path)] }
                     .grep(/@@HOMEBREW_(PREFIX|CELLAR|REPOSITORY)@@/)
  abort("Unrelocated Homebrew placeholders remain:\n#{leftovers.uniq.join("\n")}") unless leftovers.empty?

  relocated
end

entries = options[:lock] ? read_lock(options[:lock]) : resolve_lock(options[:formula], options[:version], options[:tag])
write_lock(options[:write_lock], entries) if options[:write_lock]

root = File.expand_path(options[:output])
cache = File.expand_path(options[:cache])
FileUtils.rm_rf(root)
FileUtils.mkdir_p([File.join(root, 'Cellar'), File.join(root, 'opt'), cache])

token_cache = {}
entries.each do |entry|
  puts "Fetching #{entry.fetch('name')} #{entry.fetch('version')} (#{entry.fetch('bottle_tag')})"
  archive = download_blob(entry, cache, token_cache)
  run!('tar', '-xzf', archive, '-C', File.join(root, 'Cellar'))
  top = capture!('tar', '-tzf', archive).lines.first.to_s.strip.sub(%r{/\z}, '')
  parts = top.split('/')[0, 2]
  abort("Unexpected bottle root path for #{entry.fetch('name')}: #{top}") unless parts.length == 2

  opt_link = File.join(root, 'opt', entry.fetch('name'))
  FileUtils.rm_f(opt_link)
  FileUtils.ln_s(File.join('..', 'Cellar', parts[0], parts[1]), opt_link)
end

relocated = relocate_macho!(root)
qt_prefix = File.join(root, 'opt', options[:formula])
qt_version = capture!(File.join(qt_prefix, 'bin', 'qmake'), '-query', 'QT_VERSION').strip
abort("Expected Qt #{options[:version]}, got #{qt_version}") if options[:version] && qt_version != options[:version]

qt_core = File.join(qt_prefix, 'lib', 'QtCore.framework', 'Versions', '5', 'QtCore')
archs = capture!('lipo', '-archs', qt_core).split
abort("QtCore is missing x86_64 slice: #{archs.join(' ')}") unless archs.include?('x86_64')

puts "Relocated Mach-O references: #{relocated}"
puts "Qt prefix: #{qt_prefix}"
puts "Qt version: #{qt_version}"
puts "Bottle entries: #{entries.length}"
