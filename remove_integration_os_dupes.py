#!/usr/bin/env python3
"""Remove duplicate IntegrationOS entries added by add_integration_os.py."""

import hashlib
import re

PBXPROJ = "/Users/stephtapera/Desktop/AMEN/AMENAPP copy/AMENAPP.xcodeproj/project.pbxproj"
INTEGRATION_ROOT = "AMENAPP/IntegrationOS"

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
    ("", "ExternalIntegrationView.swift"),
]

subdirs = []
for subdir, _ in INTEGRATION_FILES:
    if subdir and subdir not in subdirs:
        subdirs.append(subdir)

def make_uuid(seed):
    return hashlib.sha256(seed.encode()).hexdigest()[:24].upper()

def file_ref_uuid(rel_path):
    return make_uuid("fileref:" + rel_path)

def build_file_uuid(rel_path):
    return make_uuid("buildfile:" + rel_path)

def group_uuid(name):
    return make_uuid("group:IntegrationOS/" + name)

INTEGRATION_GROUP_UUID = group_uuid("ROOT")
all_uuids = set()
all_uuids.add(INTEGRATION_GROUP_UUID)
for subdir in subdirs:
    all_uuids.add(group_uuid(subdir))
for subdir, fname in INTEGRATION_FILES:
    rel = f"{INTEGRATION_ROOT}/{subdir}/{fname}" if subdir else f"{INTEGRATION_ROOT}/{fname}"
    all_uuids.add(file_ref_uuid(rel))
    all_uuids.add(build_file_uuid(rel))

with open(PBXPROJ, "r") as fh:
    lines = fh.readlines()

out = []
skip_block = False
skip_depth = 0

i = 0
while i < len(lines):
    line = lines[i]

    # Check if any generated UUID appears on this line
    has_our_uuid = any(u in line for u in all_uuids)

    if has_our_uuid:
        # If this line opens a multi-line block (ends with `= {`), skip the block
        stripped = line.strip()
        if stripped.endswith("= {") or ("= {\n" in line):
            # Skip until matching closing `};`
            depth = 1
            i += 1
            while i < len(lines) and depth > 0:
                if "{" in lines[i] and not lines[i].strip().startswith("//"):
                    depth += lines[i].count("{") - lines[i].count("}")
                    if depth <= 0:
                        break
                i += 1
            i += 1  # skip the `};` line
            continue
        else:
            # Single-line reference — just drop it
            i += 1
            continue
    else:
        out.append(line)
        i += 1

content = "".join(out)
with open(PBXPROJ, "w") as fh:
    fh.write(content)

print(f"Removed {len(all_uuids)} UUID entries from pbxproj")
print("Filesystem sync group will handle IntegrationOS automatically.")
