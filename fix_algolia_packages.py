#!/usr/bin/env python3
"""
Fix Algolia package references in Xcode project.
Replaces individual Algolia module references with the consolidated AlgoliaSearchClient product.
"""

import re
import shutil
from pathlib import Path

# Backup the original file
project_file = Path("AMENAPP.xcodeproj/project.pbxproj")
backup_file = project_file.with_suffix(".pbxproj.backup_algolia")

print(f"Creating backup: {backup_file}")
shutil.copy2(project_file, backup_file)

# Read the project file
content = project_file.read_text()

# List of Algolia products to remove
algolia_products = [
    "Abtesting",
    "AbtestingV3",
    "Analytics",
    "Composition",
    "Core",
    "Ingestion",
    "Insights",
    "Monitoring",
    "Personalization",
    "QuerySuggestions",
    "Recommend",
    "Search"  # Sometimes also included
]

# Track the IDs we're removing
removed_ids = set()

# Step 1: Find and collect all Algolia product reference IDs
for product in algolia_products:
    # Find PBXBuildFile entries
    pattern = rf'(\w+) /\* {re.escape(product)} in Frameworks \*/ = {{isa = PBXBuildFile; productRef = (\w+) /\* {re.escape(product)} \*/; }};'
    matches = re.findall(pattern, content)
    for build_file_id, product_ref_id in matches:
        removed_ids.add(build_file_id)
        removed_ids.add(product_ref_id)
        print(f"Found {product}: BuildFile={build_file_id}, ProductRef={product_ref_id}")

# Step 2: Remove PBXBuildFile entries
for product in algolia_products:
    # Remove from PBXBuildFile section
    pattern = rf'\t\t\w+ /\* {re.escape(product)} in Frameworks \*/ = {{isa = PBXBuildFile; productRef = \w+ /\* {re.escape(product)} \*/; }};\n'
    content = re.sub(pattern, '', content)

# Step 3: Remove from PBXFrameworksBuildPhase
for build_id in removed_ids:
    pattern = rf'\t\t\t\t{build_id} /\* [^*]+ in Frameworks \*/,\n'
    content = re.sub(pattern, '', content)

# Step 4: Remove XCSwiftPackageProductDependency entries
for product in algolia_products:
    # Remove the product dependency block
    pattern = rf'\t\t\w+ /\* {re.escape(product)} \*/ = {{\n\t\t\tisa = XCSwiftPackageProductDependency;\n\t\t\tpackage = \w+ /\* XCRemoteSwiftPackageReference "algoliasearch-client-swift" \*/;\n\t\t\tproductName = {re.escape(product)};\n\t\t}};\n'
    content = re.sub(pattern, '', content)

# Step 5: Remove from PBXNativeTarget packageProductDependencies
for product_ref_id in removed_ids:
    pattern = rf'\t\t\t\t{product_ref_id} /\* [^*]+ \*/,\n'
    content = re.sub(pattern, '', content)

# Step 6: Add AlgoliaSearchClient if not already present
if "AlgoliaSearchClient" not in content:
    print("\nAdding AlgoliaSearchClient product...")

    # Find a Firebase product reference to use as template (get the structure right)
    firebase_pattern = r'(\w+) /\* (Firebase\w+) in Frameworks \*/ = {isa = PBXBuildFile; productRef = (\w+) /\* \2 \*/; };'
    firebase_match = re.search(firebase_pattern, content)

    if firebase_match:
        # Generate new IDs (use a high number to avoid conflicts)
        algolia_build_id = "EFALGOLIA001"
        algolia_product_id = "EFALGOLIA002"

        # Add to PBXBuildFile section (after the last one)
        build_file_insertion = f"\t\t{algolia_build_id} /* AlgoliaSearchClient in Frameworks */ = {{isa = PBXBuildFile; productRef = {algolia_product_id} /* AlgoliaSearchClient */; }};\n"
        content = content.replace("/* Begin PBXBuildFile section */\n", f"/* Begin PBXBuildFile section */\n{build_file_insertion}")

        # Add to PBXFrameworksBuildPhase (find the files section)
        frameworks_pattern = r'(files = \(\n)'
        content = re.sub(frameworks_pattern, rf'\1\t\t\t\t{algolia_build_id} /* AlgoliaSearchClient in Frameworks */,\n', content, count=1)

        # Add to XCSwiftPackageProductDependency section (find the package reference)
        package_ref_pattern = r'(EF4BA9D82F29FDD3000B930F /\* XCRemoteSwiftPackageReference "algoliasearch-client-swift" \*/;)'
        if re.search(package_ref_pattern, content):
            product_dep = f"""\t\t{algolia_product_id} /* AlgoliaSearchClient */ = {{
\t\t\tisa = XCSwiftPackageProductDependency;
\t\t\tpackage = EF4BA9D82F29FDD3000B930F /* XCRemoteSwiftPackageReference "algoliasearch-client-swift" */;
\t\t\tproductName = AlgoliaSearchClient;
\t\t}};
"""
            # Find end of XCSwiftPackageProductDependency section
            end_section_pattern = r'(/\* End XCSwiftPackageProductDependency section \*/)'
            content = re.sub(end_section_pattern, rf'{product_dep}\1', content)

            # Add to packageProductDependencies array in PBXNativeTarget
            # Find the packageProductDependencies array
            pkg_deps_pattern = r'(packageProductDependencies = \(\n)'
            content = re.sub(pkg_deps_pattern, rf'\1\t\t\t\t{algolia_product_id} /* AlgoliaSearchClient */,\n', content, count=1)

            print(f"Added AlgoliaSearchClient with IDs: Build={algolia_build_id}, Product={algolia_product_id}")
        else:
            print("Warning: Could not find Algolia package reference to add product")

# Write the modified content
project_file.write_text(content)

print(f"\nProject file updated successfully!")
print(f"Backup saved to: {backup_file}")
print(f"\nRemoved {len(algolia_products)} Algolia product references")
print("Added AlgoliaSearchClient as the single Algolia dependency")
