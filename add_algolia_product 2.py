#!/usr/bin/env python3
import re

# Read the project file
with open("AMENAPP.xcodeproj/project.pbxproj", "r") as f:
    content = f.read()

# IDs for the new AlgoliaSearchClient product
BUILD_ID = "EFALGOLIA001"
PRODUCT_ID = "EFALGOLIA002"

# 1. Add to PBXBuildFile section
build_file_line = f"\t\t{BUILD_ID} /* AlgoliaSearchClient in Frameworks */ = {{isa = PBXBuildFile; productRef = {PRODUCT_ID} /* AlgoliaSearchClient */; }};\n"

# Find the first PBXBuildFile entry and add before it
build_section_start = content.find("/* Begin PBXBuildFile section */")
first_entry_start = content.find("\t\t", build_section_start)
content = content[:first_entry_start] + build_file_line + content[first_entry_start:]

print(f"✓ Added PBXBuildFile entry")

# 2. Add to PBXFrameworksBuildPhase files array
# Find the first occurrence of "files = (\n" in a PBXFrameworksBuildPhase
frameworks_phase = content.find("isa = PBXFrameworksBuildPhase")
files_start = content.find("files = (\n", frameworks_phase)
files_insert_pos = content.find("\n", files_start) + 1
framework_entry = f"\t\t\t\t{BUILD_ID} /* AlgoliaSearchClient in Frameworks */,\n"
content = content[:files_insert_pos] + framework_entry + content[files_insert_pos:]

print(f"✓ Added to PBXFrameworksBuildPhase")

# 3. Add XCSwiftPackageProductDependency entry
product_dep = f"""\t\t{PRODUCT_ID} /* AlgoliaSearchClient */ = {{
\t\t\tisa = XCSwiftPackageProductDependency;
\t\t\tpackage = EF4BA9D82F29FDD3000B930F /* XCRemoteSwiftPackageReference "algoliasearch-client-swift" */;
\t\t\tproductName = AlgoliaSearchClient;
\t\t}};
"""

# Find the end of XCSwiftPackageProductDependency section
end_section = "/* End XCSwiftPackageProductDependency section */"
end_pos = content.find(end_section)
content = content[:end_pos] + product_dep + content[end_pos:]

print(f"✓ Added XCSwiftPackageProductDependency")

# 4. Add to packageProductDependencies in PBXNativeTarget
# Find the first packageProductDependencies array
pkg_deps = content.find("packageProductDependencies = (")
if pkg_deps != -1:
    insert_pos = content.find("\n", pkg_deps) + 1
    pkg_entry = f"\t\t\t\t{PRODUCT_ID} /* AlgoliaSearchClient */,\n"
    content = content[:insert_pos] + pkg_entry + content[insert_pos:]
    print(f"✓ Added to packageProductDependencies")

# Write back
with open("AMENAPP.xcodeproj/project.pbxproj", "w") as f:
    f.write(content)

print(f"\n✅ Successfully added AlgoliaSearchClient product to project!")
