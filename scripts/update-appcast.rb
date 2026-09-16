#!/usr/bin/env ruby
# frozen_string_literal: true

require "cgi"
require "time"

unless [7, 8].include?(ARGV.length)
  warn <<~USAGE
    Usage: ruby scripts/update-appcast.rb \
      VERSION BUILD MINIMUM_SYSTEM_VERSION DMG_URL ED_SIGNATURE DMG_LENGTH RELEASE_NOTES_FILE [APPCAST_PATH]
  USAGE
  exit 2
end

version, build, minimum_system_version, dmg_url, ed_signature, dmg_length, notes_path, appcast_path = ARGV
appcast_path ||= File.expand_path("../appcast.xml", __dir__)

raise "VERSION must not be empty." if version.nil? || version.empty?
raise "BUILD must contain only digits." unless build.match?(/\A\d+\z/)
raise "MINIMUM_SYSTEM_VERSION must not be empty." if minimum_system_version.nil? || minimum_system_version.empty?
raise "DMG_URL must use HTTPS." unless dmg_url.start_with?("https://")
raise "ED_SIGNATURE must not be empty." if ed_signature.nil? || ed_signature.empty?
raise "DMG_LENGTH must contain only digits." unless dmg_length.match?(/\A\d+\z/)
raise "Release notes file does not exist: #{notes_path}" unless File.file?(notes_path)
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

release_notes = File.readlines(notes_path, chomp: true)
description = notes_to_html(release_notes)
description = "<p>Status Trio #{xml_escape(version)} is available.</p>" if description.empty?

pub_date = Time.now.utc.strftime("%a, %d %b %Y %H:%M:%S +0000")
item = <<~XML.gsub(/^/, "    ").rstrip
  <item>
    <title>Version #{xml_escape(version)} (Build #{xml_escape(build)}) （English + 中文， 中文在下方）</title>
    <pubDate>#{pub_date}</pubDate>
    <sparkle:version>#{xml_escape(build)}</sparkle:version>
    <sparkle:shortVersionString>#{xml_escape(version)}</sparkle:shortVersionString>
    <sparkle:minimumSystemVersion>#{xml_escape(minimum_system_version)}</sparkle:minimumSystemVersion>
    <description><![CDATA[#{cdata_escape(description)}]]></description>
    <enclosure url="#{xml_escape(dmg_url)}"
               type="application/octet-stream"
               sparkle:edSignature="#{xml_escape(ed_signature)}"
               length="#{xml_escape(dmg_length)}" />
  </item>
XML

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
