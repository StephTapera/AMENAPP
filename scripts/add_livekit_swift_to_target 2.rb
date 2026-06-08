#!/usr/bin/env ruby
require 'xcodeproj'

PROJ_PATH   = File.expand_path("../AMENAPP.xcodeproj", __dir__)
TARGET_NAME = "AMENAPP"
SOURCE_ROOT = File.expand_path("../AMENAPP/AMENAPP", __dir__)
NEW_FILE    = "ConnectSpaces/Live/AmenLivekitLiveRoomProvider.swift"

project = Xcodeproj::Project.open(PROJ_PATH)
target  = project.targets.find { |t| t.name == TARGET_NAME }
abort "❌ Target not found." unless target

abs = File.join(SOURCE_ROOT, NEW_FILE)
abort "❌ File not on disk: #{abs}" unless File.exist?(abs)

if project.files.any? { |f| f.real_path.to_s == abs rescue false }
  puts "✓  Already in project."; exit 0
end

def walk_group(g, path)
  return g if g.real_path.to_s == path
  g.groups.each { |c| r = walk_group(c, path); return r if r }; nil
end
def find_or_create(parent, name)
  parent.groups.find { |g| g.name == name || g.path == name } || parent.new_group(name, name)
end

root = project.groups.lazy.map { |g| walk_group(g, SOURCE_ROOT) }.find(&:itself) || project.main_group
current = root
NEW_FILE.split("/")[0..-2].each { |part| current = find_or_create(current, part) }
ref = current.new_file(abs)
target.source_build_phase.add_file_reference(ref)
project.save
puts "✅ Added: #{NEW_FILE}"
