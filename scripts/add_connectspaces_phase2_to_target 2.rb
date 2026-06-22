#!/usr/bin/env ruby
# add_connectspaces_phase2_to_target.rb
# Adds 3 new Phase 2 ConnectSpaces Swift files to the AMENAPP Xcode target:
#   - AmenFirebaseLiveRoomProvider.swift (Live/)
#   - AmenStoreKitService.swift (Monetization/)
#   - AmenStripeOnboardingService.swift (Monetization/)

require 'xcodeproj'

PROJ_PATH   = File.expand_path("../AMENAPP.xcodeproj", __dir__)
TARGET_NAME = "AMENAPP"
SOURCE_ROOT = File.expand_path("../AMENAPP/AMENAPP", __dir__)

NEW_FILES = [
  "ConnectSpaces/Live/AmenFirebaseLiveRoomProvider.swift",
  "ConnectSpaces/Monetization/AmenStoreKitService.swift",
  "ConnectSpaces/Monetization/AmenStripeOnboardingService.swift",
]

puts "Opening #{PROJ_PATH}"
project = Xcodeproj::Project.open(PROJ_PATH)
target  = project.targets.find { |t| t.name == TARGET_NAME }
abort "❌ Target '#{TARGET_NAME}' not found." unless target

def find_or_create_group(parent, name)
  parent.groups.find { |g| g.name == name || g.path == name } || parent.new_group(name, name)
end

def walk_group(group, real_path)
  return group if group.real_path.to_s == real_path
  group.groups.each { |g| r = walk_group(g, real_path); return r if r }
  nil
end

root_group = project.groups.lazy.map { |g| walk_group(g, SOURCE_ROOT) }.find(&:itself)
root_group ||= project.main_group

added = 0; skipped = 0

NEW_FILES.each do |rel|
  abs = File.join(SOURCE_ROOT, rel)
  unless File.exist?(abs)
    puts "  ⚠️  Not on disk, skipping: #{rel}"; skipped += 1; next
  end

  if project.files.any? { |f| f.real_path.to_s == abs rescue false }
    puts "  ✓  Already in project: #{File.basename(rel)}"; skipped += 1; next
  end

  current = root_group
  rel.split("/")[0..-2].each { |part| current = find_or_create_group(current, part) }

  ref = current.new_file(abs)
  target.source_build_phase.add_file_reference(ref)
  puts "  ✅ Added: #{rel}"
  added += 1
end

project.save
puts "\nDone. Added #{added} file(s), skipped #{skipped}."
