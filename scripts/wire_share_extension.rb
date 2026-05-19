# encoding: utf-8
# Wires AMENShareExtension as an app-extension target into AMENAPP.xcodeproj.
# Idempotent: safe to re-run; will not duplicate the target if it already exists.

require "xcodeproj"

PROJECT_PATH = File.expand_path("../AMENAPP.xcodeproj", __dir__)
EXT_NAME     = "AMENShareExtension"
EXT_DIR      = File.expand_path("../#{EXT_NAME}", __dir__)
BUNDLE_ID    = "tapera.AMENAPP.#{EXT_NAME}"
TEAM         = "FGLL559H83"
DEPLOY_TGT   = "26.2"
SWIFT_VER    = "5.0"

proj = Xcodeproj::Project.open(PROJECT_PATH)
main = proj.targets.find { |t| t.name == "AMENAPP" } or abort "Main target not found"

existing = proj.targets.find { |t| t.name == EXT_NAME }
if existing
  puts "Target #{EXT_NAME} already exists. Skipping creation."
  ext_target = existing
else
  puts "Creating new app-extension target: #{EXT_NAME}"
  ext_target = proj.new_target(
    :app_extension,
    EXT_NAME,
    :ios,
    DEPLOY_TGT,
    proj.products_group,
    :swift
  )
end

# --- Configure build settings on both Debug & Release ---
ext_target.build_configurations.each do |cfg|
  bs = cfg.build_settings
  bs["PRODUCT_BUNDLE_IDENTIFIER"]      = BUNDLE_ID
  bs["PRODUCT_NAME"]                    = "$(TARGET_NAME)"
  bs["DEVELOPMENT_TEAM"]                = TEAM
  bs["IPHONEOS_DEPLOYMENT_TARGET"]      = DEPLOY_TGT
  bs["SWIFT_VERSION"]                   = SWIFT_VER
  bs["CODE_SIGN_STYLE"]                 = "Automatic"
  bs["CODE_SIGN_ENTITLEMENTS"]          = "#{EXT_NAME}/#{EXT_NAME}.entitlements"
  bs["INFOPLIST_FILE"]                  = "#{EXT_NAME}/Info.plist"
  bs["SKIP_INSTALL"]                    = "YES"
  bs["GENERATE_INFOPLIST_FILE"]         = "NO"
  bs["TARGETED_DEVICE_FAMILY"]          = "1,2"
  bs["LD_RUNPATH_SEARCH_PATHS"]         = "$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks"
  bs["CURRENT_PROJECT_VERSION"]         = "1"
  bs["MARKETING_VERSION"]               = "1.0"
  bs["ENABLE_USER_SCRIPT_SANDBOXING"]   = "YES"
  bs["SWIFT_EMIT_LOC_STRINGS"]          = "YES"
end

# --- Create file group + add source files ---
group = proj.main_group[EXT_NAME] || proj.main_group.new_group(EXT_NAME, EXT_NAME)

src_files = ["ShareExtensionViewController.swift", "ShareModels.swift"]
resource_files = [] # Info.plist is referenced via INFOPLIST_FILE, not bundled as a resource

src_files.each do |fname|
  fpath = File.join(EXT_DIR, fname)
  unless File.exist?(fpath)
    abort "Missing source: #{fpath}"
  end
  existing_ref = group.files.find { |f| f.display_name == fname }
  file_ref = existing_ref || group.new_reference(fpath)
  # Avoid duplicate build files
  unless ext_target.source_build_phase.files_references.include?(file_ref)
    ext_target.source_build_phase.add_file_reference(file_ref)
  end
end

# Also add Info.plist & entitlements as file references (not in build phases) for visibility in Xcode
["Info.plist", "#{EXT_NAME}.entitlements"].each do |fname|
  fpath = File.join(EXT_DIR, fname)
  next unless File.exist?(fpath)
  unless group.files.any? { |f| f.display_name == fname }
    group.new_reference(fpath)
  end
end

# --- Embed extension in main app ---
embed_phase = main.copy_files_build_phases.find { |p| p.dst_subfolder_spec == "13" }
embed_phase ||= main.new_copy_files_build_phase("Embed Foundation Extensions").tap do |ph|
  ph.symbol_dst_subfolder_spec = :plug_ins
end

product_ref = ext_target.product_reference
unless embed_phase.files_references.include?(product_ref)
  bf = embed_phase.add_file_reference(product_ref)
  bf.settings = { "ATTRIBUTES" => ["RemoveHeadersOnCopy"] }
end

# --- Add dependency from main app on extension target ---
unless main.dependencies.any? { |d| d.target == ext_target }
  main.add_dependency(ext_target)
end

proj.save
puts "Done. Target #{EXT_NAME} wired into #{PROJECT_PATH}"
