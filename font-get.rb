#!/usr/bin/ruby

require 'excon'
require 'json'
require 'optparse'
require 'yaml'

def fuzzy_match?(a, b)
  a = a.bytes
  b.bytes.each do |char|
    idx = a.find_index(char)
    return unless idx

    a.slice!(idx)
  end

  true
end

def find_files(items, family)
  items.select { |x| fuzzy_match? x['family'].delete(' ').downcase, family.downcase }
end

def items_to_install(items, families)
  families.map { |f| [f, find_files(items, f)] }.to_h
end

def files_to_install(items, families)
  items_to_install(items, families).map do |family, items|
    install_hash = items.map do |x|
      x['files'].map do |f, url|
        ["#{x['family'].delete(' ')}-#{f}.ttf", url]
      end
    end.flatten(1).to_h

    [family, install_hash]
  end.to_h
end

def fetch
  key = ENV.fetch('GOOGLE_FONTS_API_KEY')
  response = Excon.get(
    "https://content.googleapis.com/webfonts/v1/webfonts?sort=popularity&key=#{key}",
    headers: {
      'User-Agent' => 'github.com/diane/font-get',
      'Accept' => '*/*',
      'Accept-Language' => 'en-US,en;q=0.5',
      'Referer' => 'https://github.com/dianelooney/font-get',
    },
  )
  JSON.parse(response.body)['items']
end

def install_flow(families, options)
  return puts 'Please choose fonts to install' unless families.any?

  items = fetch
  installs = files_to_install(items, families)
  puts 'The following fonts will be installed.'
  puts installs.to_yaml

  return if options.fetch(:dry, false)

  unless options.fetch(:yes)
    puts 'Continue? Y/n'
    yn =  STDIN.gets.chomp
    return unless yn == 'Y'
  end

  installs.values.inject({}, &:merge).each do |name, url|
    path = "~/.local/share/fonts/#{name}"
    cmd = "wget --quiet -O #{path} #{url}"
    puts cmd
    `#{cmd}`
  end
end

options = {}

OptionParser.new do |opts|
  opts.banner = "Usage: example.rb [options]"

  opts.on("-Y", "--yes", "Auto-accept the install candidates") do |v|
    options[:yes] = v
  end
  opts.on("-D", "--dry-run", "Don't install anything, just show what would be installed") do |v|
    options[:dry] = v
  end
end.parse!

families = ARGV

install_flow(families, options)
