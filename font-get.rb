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

def family_items(items, families)
  families.map do |f|
    [f, items.select { |x| fuzzy_match? x['family'].delete(' ').downcase, f.downcase }]
  end.to_h
end

def category_items(items, categories)
  categories.map do |category|
    [category, items.select { |x| x['category'].downcase == category.downcase }]
  end.to_h
end

def files_to_install(items, families, categories)
  groups = {
    family: family_items(items, families),
    category: category_items(items, categories),
  }

  groups.transform_values do |group|
    group.map do |family, items|
      install_hash = items.map do |x|
        x['files'].map do |f, url|
          ["#{x['family'].delete(' ')}-#{f}.ttf", url]
        end
      end.flatten(1).to_h

      [family, install_hash]
    end.to_h
  end
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
  items = fetch
  installs = files_to_install(items, families, options.fetch(:categories))
  puts 'The following fonts will be installed.'
  puts installs.to_yaml

  return if options.fetch(:dry)

  unless options.fetch(:yes)
    puts 'Continue? Y/n'
    yn =  STDIN.gets.chomp
    return unless yn == 'Y'
  end

  installs.values.each do |group|
    group.values.inject({}, &:merge).each do |name, url|
      path = "~/.local/share/fonts/#{name}"
      cmd = "wget --quiet -O #{path} #{url}"
      puts cmd
      `#{cmd}`
    end
  end
end

options = {}

OptionParser.new do |opts|
  opts.banner = "Usage: example.rb [options]"

  options[:categories] = []
  opts.on("-C x,y,z", Array, "Install all fonts from these categories") do |list|
    options[:categories] = list
  end

  options[:yes] = false
  opts.on("-Y", "--yes", "Auto-accept the install candidates") do |v|
    options[:yes] = v
  end

  options[:dry] = false
  opts.on("-D", "--dry-run", "Don't install anything, just show what would be installed") do |v|
    options[:dry] = v
  end
end.parse!

families = ARGV

install_flow(families, options)
