#!/usr/bin/env python3
import re

# Read the project file
with open("AMENAPP.xcodeproj/project.pbxproj", "r") as f:
    content = f.read()

print("Removing Algolia package from project...")

# 1. Remove the AlgoliaSearchClient PBXBuildFile we just added
content = re.sub(r'\t\tEFALGOLIA001 /\* AlgoliaSearchClient in Frameworks \*/ = \{isa = PBXBuildFile; productRef = EFALGOLIA002 /\* AlgoliaSearchClient \*/; \};\n', '', content)
print("✓ Removed AlgoliaSearchClient PBXBuildFile")

# 2. Remove from PBXFrameworksBuildPhase
content = re.sub(r'\t\t\t\tEFALGOLIA001 /\* AlgoliaSearchClient in Frameworks \*/,\n', '', content)
print("✓ Removed from PBXFrameworksBuildPhase")

# 3. Remove XCSwiftPackageProductDependency
pattern = r'\t\tEFALGOLIA002 /\* AlgoliaSearchClient \*/ = \{\n\t\t\tisa = XCSwiftPackageProductDependency;\n\t\t\tpackage = EF4BA9D82F29FDD3000B930F /\* XCRemoteSwiftPackageReference "algoliasearch-client-swift" \*/;\n\t\t\tproductName = AlgoliaSearchClient;\n\t\t\};\n'
content = re.sub(pattern, '', content)
print("✓ Removed XCSwiftPackageProductDependency")

# 4. Remove from packageProductDependencies
content = re.sub(r'\t\t\t\tEFALGOLIA002 /\* AlgoliaSearchClient \*/,\n', '', content)
print("✓ Removed from packageProductDependencies")

# 5. Remove the Algolia package reference entirely
content = re.sub(r'\t\t\t\tEF4BA9D82F29FDD3000B930F /\* XCRemoteSwiftPackageReference "algoliasearch-client-swift" \*/,\n', '', content)
print("✓ Removed package reference from packageReferences")

# 6. Remove the XCRemoteSwiftPackageReference definition
pattern = r'\t\tEF4BA9D82F29FDD3000B930F /\* XCRemoteSwiftPackageReference "algoliasearch-client-swift" \*/ = \{\n\t\t\tisa = XCRemoteSwiftPackageReference;\n\t\t\trepositoryURL = "[^"]+algoliasearch[^"]+";[^}]+\};\n'
content = re.sub(pattern, '', content)
print("✓ Removed XCRemoteSwiftPackageReference definition")

# Write back
with open("AMENAPP.xcodeproj/project.pbxproj", "w") as f:
    f.write(content)

print("\n✅ Successfully removed Algolia package from project!")
print("The app doesn't use Algolia, so this dependency is not needed.")
