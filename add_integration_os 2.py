#!/usr/bin/env python3
"""Add IntegrationOS files to AMEN Xcode project."""

import hashlib
import re
import os

PBXPROJ = "/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP.xcodeproj/project.pbxproj"
INTEGRATION_ROOT = "AMENAPP/IntegrationOS"  # relative to project SOURCE_ROOT

# All new files: (subdir, filename)
# The existing ExternalIntegrationView.swift is already in root of IntegrationOS
INTEGRATION_FILES = [
    ("Contracts", "ExternalOSContracts.swift"),
    ("Spine", "ProviderRegistry.swift"),
    ("Spine", "ConsentLedgerService.swift"),
    ("Spine", "CostGovernorService.swift"),
    ("Spine", "WebhookRouterService.swift"),
    ("Spine", "IntegrationHealthDashboard.swift"),
    ("Spine", "ManageConnectionsView.swift"),
    ("Spine", "JITConsentSheet.swift"),
    ("Maps", "MapProviderAdapter.swift"),
    ("Maps", "ChurchDiscoveryService.swift"),
    ("Maps", "ChurchDiscoveryView.swift"),
    ("Maps", "PlanVisitView.swift"),
    ("Transport", "CarpoolModels.swift"),
    ("Transport", "TransportCoordinatorService.swift"),
    ("Transport", "VisitPlanningView.swift"),
    ("Calendar", "CalendarProviderAdapter.swift"),
    ("Calendar", "AmenCalendarService.swift"),
    ("Calendar", "CalendarConsentView.swift"),
    ("Media", "MediaProviderAdapter.swift"),
    ("Media", "SermonMediaTransformService.swift"),
    ("Media", "SermonStudyPacket.swift"),
    ("Media", "MediaObjectComposerView.swift"),
    ("Events", "EventProviderAdapter.swift"),
    ("Events", "AmenEventService.swift"),
    ("Events", "AmenEventModels.swift"),
    ("Events", "EventDetailView.swift"),
    ("Career", "OpportunityModels.swift"),
    ("Career", "OpportunityService.swift"),
    ("Career", "OpportunityFeedView.swift"),
    ("Contacts", "ContactDiscoveryService.swift"),
    ("Contacts", "SafeIntroductionModels.swift"),
    ("Contacts", "SafeIntroductionService.swift"),
    ("Contacts", "ContactDiscoveryView.swift"),
    ("Health", "HealthProviderAdapter.swift"),
    ("Health", "WellnessIntegrationService.swift"),
    ("Health", "HealthWellnessView.swift"),
    ("Knowledge", "OrgKnowledgeModels.swift"),
    ("Knowledge", "OrgKnowledgeBaseService.swift"),
    ("Knowledge", "OrgAssistantService.swift"),
    ("Knowledge", "OrgAssistantView.swift"),
    ("Messaging", "BroadcastModels.swift"),
    ("Messaging", "MessagingChannelAdapter.swift"),
    ("Messaging", "BroadcastService.swift"),
    ("Messaging", "BroadcastComposerView.swift"),
    ("Messaging", "VoiceNoteService.swift"),
    # existing root file
    ("", "ExternalIntegrationView.swift"),
]

def make_uuid(seed: str) -> str:
    """Deterministic 24-char uppercase hex UUID from a seed string."""
    h = hashlib.sha256(seed.encode()).hexdigest()[:24].upper()
    return h

def file_ref_uuid(rel_path: str) -> str:
    return make_uuid("fileref:" + rel_path)

def build_file_uuid(rel_path: str) -> str:
    return make_uuid("buildfile:" + rel_path)

def group_uuid(group_name: str) -> str:
    return make_uuid("group:IntegrationOS/" + group_name)

# Collect subdirs (unique, ordered)
subdirs = []
for subdir, _ in INTEGRATION_FILES:
    if subdir and subdir not in subdirs:
        subdirs.append(subdir)

# Root IntegrationOS group
INTEGRATION_GROUP_UUID = group_uuid("ROOT")

# ── Build text fragments ────────────────────────────────────────────────────

file_ref_lines = []
build_file_lines = []
subdir_group_blocks = []
root_group_children = []
sources_entries = []

for subdir, fname in INTEGRATION_FILES:
    if subdir:
        rel_path = f"{INTEGRATION_ROOT}/{subdir}/{fname}"
    else:
        rel_path = f"{INTEGRATION_ROOT}/{fname}"

    fr_uuid = file_ref_uuid(rel_path)
    bf_uuid = build_file_uuid(rel_path)

    file_ref_lines.append(
        f"\t\t{fr_uuid} /* {fname} */ = {{isa = PBXFileReference; "
        f"includeInIndex = 1; lastKnownFileType = sourcecode.swift; "
        f"name = {fname}; path = {rel_path}; sourceTree = \"<group>\"; }};"
    )
    build_file_lines.append(
        f"\t\t{bf_uuid} /* {fname} in Sources */ = "
        f"{{isa = PBXBuildFile; fileRef = {fr_uuid} /* {fname} */; }};"
    )
    sources_entries.append(
        f"\t\t\t\t{bf_uuid} /* {fname} in Sources */,"
    )

# Per-subdir group blocks
for subdir in subdirs:
    sg_uuid = group_uuid(subdir)
    files_in_subdir = [(f, s) for (s, f) in [(s2, f2) for s2, f2 in INTEGRATION_FILES if s2 == subdir]]
    child_refs = "\n".join(
        f"\t\t\t\t{file_ref_uuid(INTEGRATION_ROOT + '/' + subdir + '/' + f)} /* {f} */,"
        for f, _ in files_in_subdir
    )
    subdir_group_blocks.append(
        f"\t\t{sg_uuid} /* {subdir} */ = {{\n"
        f"\t\t\tisa = PBXGroup;\n"
        f"\t\t\tchildren = (\n"
        f"{child_refs}\n"
        f"\t\t\t);\n"
        f"\t\t\tpath = {subdir};\n"
        f"\t\t\tsourceTree = \"<group>\";\n"
        f"\t\t}};"
    )
    root_group_children.append(f"\t\t\t\t{sg_uuid} /* {subdir} */,")

# Root IntegrationOS file (ExternalIntegrationView.swift)
root_file_ref = file_ref_uuid(f"{INTEGRATION_ROOT}/ExternalIntegrationView.swift")
root_group_children.append(f"\t\t\t\t{root_file_ref} /* ExternalIntegrationView.swift */,")

integration_group_block = (
    f"\t\t{INTEGRATION_GROUP_UUID} /* IntegrationOS */ = {{\n"
    f"\t\t\tisa = PBXGroup;\n"
    f"\t\t\tchildren = (\n"
    + "\n".join(root_group_children) + "\n"
    f"\t\t\t);\n"
    f"\t\t\tpath = {INTEGRATION_ROOT};\n"
    f"\t\t\tsourceTree = \"<group>\";\n"
    f"\t\t}};"
)

# ── Patch pbxproj ───────────────────────────────────────────────────────────

with open(PBXPROJ, "r") as fh:
    content = fh.read()

# 1. Inject file refs before "/* End PBXFileReference section */"
new_refs = "\n".join(file_ref_lines) + "\n"
content = content.replace(
    "/* End PBXFileReference section */",
    new_refs + "/* End PBXFileReference section */"
)

# 2. Inject build files before "/* End PBXBuildFile section */"
new_builds = "\n".join(build_file_lines) + "\n"
content = content.replace(
    "/* End PBXBuildFile section */",
    new_builds + "/* End PBXBuildFile section */"
)

# 3. Inject group blocks before "/* End PBXGroup section */"
new_groups = "\n".join(subdir_group_blocks) + "\n" + integration_group_block + "\n"
content = content.replace(
    "/* End PBXGroup section */",
    new_groups + "/* End PBXGroup section */"
)

# 4. Add IntegrationOS group to root group children (after Config.xcconfig entry)
ROOT_GROUP_UUID = "EF8151922F184E97008912E3"
root_insert_marker = "EF3B23532F4AAC1B001DA241 /* Config.xcconfig */,"
content = content.replace(
    root_insert_marker,
    root_insert_marker + f"\n\t\t\t\t{INTEGRATION_GROUP_UUID} /* IntegrationOS */,"
)

# 5. Inject build file UUIDs into Sources build phase
# Sources phase UUID: EF8151972F184E97008912E3
SOURCES_PHASE_UUID = "EF8151972F184E97008912E3"
sources_marker = f"{SOURCES_PHASE_UUID} /* Sources */ = {{"
# Find the files = ( ... ); block inside this phase
sources_section_pattern = re.compile(
    r'(EF8151972F184E97008912E3 /\* Sources \*/ = \{[^}]*files = \()',
    re.DOTALL
)
new_sources_entries = "\n" + "\n".join(sources_entries) + "\n"
content = sources_section_pattern.sub(
    lambda m: m.group(0) + new_sources_entries,
    content,
    count=1
)

with open(PBXPROJ, "w") as fh:
    fh.write(content)

print(f"✓ Added {len(INTEGRATION_FILES)} files to Xcode project")
print(f"  IntegrationOS group UUID: {INTEGRATION_GROUP_UUID}")
print(f"  Subdirectory groups: {', '.join(subdirs)}")
