#!/usr/bin/env ruby
# add_livekit_spm.rb
# Adds LiveKit client-sdk-swift as an SPM dependency to the AMENAPP Xcode target.
# Run once after cloning: ruby scripts/add_livekit_spm.rb

require 'xcodeproj'

PROJ_PATH    = File.expand_path("../AMENAPP.xcodeproj", __dir__)
TARGET_NAME  = "AMENAPP"
PACKAGE_URL  = "https://github.com/livekit/client-sdk-swift"
PRODUCT_NAME = "LiveKit"
MIN_VERSION  = "2.0.0"

puts "Opening #{PROJ_PATH}"
project = Xcodeproj::Project.open(PROJ_PATH)
target  = project.targets.find { |t| t.name == TARGET_NAME }
abort "❌ Target '#{TARGET_NAME}' not found." unless target

# Check if already added
already = project.root_object.package_references&.any? do |ref|
  ref.respond_to?(:repository_url) && ref.repository_url == PACKAGE_URL
end
if already
  puts "✓  LiveKit package already in project."
  exit 0
end

# Add remote package reference
pkg = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
pkg.repositoryURL = PACKAGE_URL
pkg.requirement    = { kind: "upToNextMajorVersion", minimumVersion: MIN_VERSION }
project.root_object.package_references ||= []
project.root_object.package_references << pkg

# Add product dependency to target
dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
dep.package      = pkg
dep.product_name = PRODUCT_NAME
target.package_product_dependencies ||= []
target.package_product_dependencies << dep

project.save
puts "✅ Added LiveKit #{MIN_VERSION}+ to target '#{TARGET_NAME}'."
puts "   Xcode will resolve the package on next open/build."
