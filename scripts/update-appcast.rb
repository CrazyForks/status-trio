#!/usr/bin/env ruby
# frozen_string_literal: true

require "cgi"
require "time"

unless [7, 8, 9].include?(ARGV.length)
  warn <<~USAGE
    Usage: ruby scripts/update-appcast.rb \
      VERSION BUILD MINIMUM_SYSTEM_VERSION DMG_URL ED_SIGNATURE DMG_LENGTH \
      RELEASE_NOTES_FILE [RELEASE_NOTES_ZH_FILE] [APPCAST_PATH]

    RELEASE_NOTES_ZH_FILE adds the Chinese variant of a localized item. When the
    eighth argument ends in .xml it is treated as APPCAST_PATH instead.
  USAGE
  exit 2
end

version, build, minimum_system_version, dmg_url, ed_signature, dmg_length, notes_path, second_arg, third_arg = ARGV

notes_zh_path = nil
appcast_path = nil

if third_arg
  notes_zh_path = second_arg
  appcast_path = third_arg
elsif second_arg
  if second_arg.end_with?(".xml")
    appcast_path = second_arg
  else
    notes_zh_path = second_arg
  end
end

appcast_path ||= File.expand_path("../appcast.xml", __dir__)

raise "VERSION must not be empty." if version.nil? || version.empty?
raise "BUILD must contain only digits." unless build.match?(/\A\d+\z/)
raise "MINIMUM_SYSTEM_VERSION must not be empty." if minimum_system_version.nil? || minimum_system_version.empty?
raise "DMG_URL must use HTTPS." unless dmg_url.start_with?("https://")
raise "ED_SIGNATURE must not be empty." if ed_signature.nil? || ed_signature.empty?
raise "DMG_LENGTH must contain only digits." unless dmg_length.match?(/\A\d+\z/)
raise "Release notes file does not exist: #{notes_path}" unless File.file?(notes_path)
raise "Chinese release notes file does not exist: #{notes_zh_path}" if notes_zh_path && !File.file?(notes_zh_path)
raise "Appcast file does not exist: #{appcast_path}" unless File.file?(appcast_path)

def xml_escape(value)
  CGI.escapeHTML(value.to_s)
end

def cdata_escape(value)
  value.to_s.gsub("]]>", "]]]]><![CDATA[>")
end

appcast = File.read(appcast_path)
if appcast.match?(%r{<sparkle:version>\s*#{Regexp.escape(build)}\s*</sparkle:version>})
  raise "Build #{build} already exists in #{appcast_path}."
end

def notes_to_html(lines)
  html = []
  list_items = []

  flush_list = lambda do
    next if list_items.empty?

    html << "<ul>#{list_items.join}</ul>"
    list_items = []
  end

  lines.map(&:strip).each do |line|
    next if line.empty?
    next if line.match?(/\A#\s+/)

    if (heading = line.match(/\A##\s+(.+)\z/))
      flush_list.call
      html << "<h2>#{xml_escape(heading[1])}</h2>"
    elsif (item = line.match(/\A(?:[-*+]|\d+\.)\s+(.+)\z/))
      list_items << "<li>#{xml_escape(item[1])}</li>"
    else
      list_items << "<li>#{xml_escape(line)}</li>"
    end
  end

  flush_list.call
  html.join
end

def notes_description(notes_path, version)
  description = notes_to_html(File.readlines(notes_path, chomp: true))
  description.empty? ? "<p>Status Trio #{xml_escape(version)} is available.</p>" : description
end

description_en = notes_description(notes_path, version)
description_zh = notes_zh_path ? notes_description(notes_zh_path, version) : nil

pub_date = Time.now.utc.strftime("%a, %d %b %Y %H:%M:%S +0000")
title_en = "Version #{xml_escape(version)} (Build #{xml_escape(build)})"
title_zh = "版本 #{xml_escape(version)}（构建 #{xml_escape(build)}）"

# Sparkle picks the variant matching the user's preferred languages, so every
# localized element needs an explicit xml:lang. Without a Chinese notes file we
# keep the single bilingual-marker item for local runs.
item_lines = []
if description_zh
  item_lines << %(<title xml:lang="en">#{title_en}</title>)
  item_lines << %(<title xml:lang="zh-Hans">#{title_zh}</title>)
else
  item_lines << %(<title>#{title_en} （English + 中文， 中文在下方）</title>)
end
item_lines << "<pubDate>#{pub_date}</pubDate>"
item_lines << "<sparkle:version>#{xml_escape(build)}</sparkle:version>"
item_lines << "<sparkle:shortVersionString>#{xml_escape(version)}</sparkle:shortVersionString>"
item_lines << "<sparkle:minimumSystemVersion>#{xml_escape(minimum_system_version)}</sparkle:minimumSystemVersion>"
if description_zh
  item_lines << %(<description xml:lang="en"><![CDATA[#{cdata_escape(description_en)}]]></description>)
  item_lines << %(<description xml:lang="zh-Hans"><![CDATA[#{cdata_escape(description_zh)}]]></description>)
else
  item_lines << %(<description><![CDATA[#{cdata_escape(description_en)}]]></description>)
end
item_lines << %(<enclosure url="#{xml_escape(dmg_url)}")
item_lines << %(           type="application/octet-stream")
item_lines << %(           sparkle:edSignature="#{xml_escape(ed_signature)}")
item_lines << %(           length="#{xml_escape(dmg_length)}" />)

item = (["    <item>"] + item_lines.map { |line| "      #{line}" } + ["    </item>"]).join("\n")

updated = appcast.dup
existing_item = appcast.match(/^[ \t]*<item\b/m)

if existing_item
  updated.insert(existing_item.begin(0), "#{item}\n")
else
  channel_end = appcast.rindex("</channel>")
  raise "Could not find </channel> in #{appcast_path}." unless channel_end

  closing_indent = appcast[0...channel_end][/[ \t]*\z/]
  indent_start = channel_end - closing_indent.length
  updated[indent_start, closing_indent.length] = "#{item}\n#{closing_indent}"
end

File.write(appcast_path, updated)
puts "Updated #{appcast_path} with build #{build}."
