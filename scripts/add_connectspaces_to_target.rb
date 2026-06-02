#!/usr/bin/env ruby
# add_connectspaces_to_target.rb
# Adds the 26 new ConnectSpaces Phase 1-5 Swift files to the AMENAPP Xcode target.

require 'xcodeproj'
require 'pathname'

PROJ_PATH  = File.expand_path("../AMENAPP.xcodeproj", __dir__)
TARGET_NAME = "AMENAPP"
SOURCE_ROOT = File.expand_path("../AMENAPP/AMENAPP", __dir__)

NEW_FILES = [
  # Root-level ConnectSpaces
  "ConnectSpaces/SpacesPhase1Contracts.swift",
  "ConnectSpaces/AmenSpaceHeroHeaderView.swift",
  "ConnectSpaces/AmenSpaceDetailView.swift",
  "ConnectSpaces/AmenSpaceNowLiveMiniPlayer.swift",
  # Monetization
  "ConnectSpaces/Monetization/AmenSpaceEntitlementService.swift",
  "ConnectSpaces/Monetization/AmenSpacePaywallView.swift",
  "ConnectSpaces/Monetization/AmenSpaceTierSelectionView.swift",
  "ConnectSpaces/Monetization/AmenSpaceHostOnboardingView.swift",
  # Events
  "ConnectSpaces/Events/AmenCalendarInviteService.swift",
  "ConnectSpaces/Events/AmenUpcomingLiveChipView.swift",
  "ConnectSpaces/Events/AmenSpaceEventDetailView.swift",
  "ConnectSpaces/Events/AmenSpaceEventsListView.swift",
  "ConnectSpaces/Events/AmenBroadcastComposerView.swift",
  # Live
  "ConnectSpaces/Live/AmenLiveRoomProviderInterface.swift",
  "ConnectSpaces/Live/AmenLiveRoomShellView.swift",
  "ConnectSpaces/Live/AmenLiveRoomGreenRoomView.swift",
  "ConnectSpaces/Live/AmenLiveQAQueueView.swift",
  "ConnectSpaces/Live/AmenLiveCaptionsOverlay.swift",
  # AIRecap
  "ConnectSpaces/AIRecap/AmenReplayRecapCard.swift",
  "ConnectSpaces/AIRecap/AmenTranscriptSearchView.swift",
  "ConnectSpaces/AIRecap/AmenStudyCompanionSheet.swift",
  "ConnectSpaces/AIRecap/AmenAutoClipBrowserView.swift",
  # Safety
  "ConnectSpaces/Safety/AmenScamShieldService.swift",
  "ConnectSpaces/Safety/AmenScamShieldAlertView.swift",
  "ConnectSpaces/Safety/AmenVerifiedHostBadgeView.swift",
  "ConnectSpaces/Safety/AmenModerationDashboardView.swift",
]

puts "Opening #{PROJ_PATH}"
project = Xcodeproj::Project.open(PROJ_PATH)

target = project.targets.find { |t| t.name == TARGET_NAME }
abort "❌ Target '#{TARGET_NAME}' not found. Available: #{project.targets.map(&:name).join(', ')}" unless target

# Find or build a group hierarchy under SOURCE_ROOT
def find_or_create_group(parent_group, name)
  existing = parent_group.groups.find { |g| g.name == name || g.path == name }
  return existing if existing
  parent_group.new_group(name, name)
end

# Find the AMENAPP/AMENAPP source group (the one whose real path is SOURCE_ROOT)
def find_group_for_path(project, real_path)
  project.groups.each do |g|
    result = walk_group(g, real_path)
    return result if result
  end
  nil
end

def walk_group(group, real_path)
  return group if group.real_path.to_s == real_path
  group.groups.each do |child|
    result = walk_group(child, real_path)
    return result if result
  end
  nil
end

root_group = find_group_for_path(project, SOURCE_ROOT)
unless root_group
  puts "⚠️  Could not auto-find group for #{SOURCE_ROOT}. Using main group."
  root_group = project.main_group
end

added = 0
skipped = 0

NEW_FILES.each do |relative_path|
  abs_path = File.join(SOURCE_ROOT, relative_path)

  unless File.exist?(abs_path)
    puts "  ⚠️  File not found on disk, skipping: #{relative_path}"
    skipped += 1
    next
  end

  # Already in project?
  already_in_project = project.files.any? { |f|
    begin; f.real_path.to_s == abs_path; rescue; false; end
  }
  if already_in_project
    puts "  ✓  Already in project: #{File.basename(relative_path)}"
    skipped += 1
    next
  end

  # Build the group hierarchy
  parts = relative_path.split("/")
  current_group = root_group
  parts[0..-2].each { |part| current_group = find_or_create_group(current_group, part) }

  file_ref = current_group.new_file(abs_path)
  target.source_build_phase.add_file_reference(file_ref)
  puts "  ✅ Added: #{relative_path}"
  added += 1
end

project.save
puts "\nDone. Added #{added} file(s), skipped #{skipped}."
