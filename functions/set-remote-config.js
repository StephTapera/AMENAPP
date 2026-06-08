/**
 * set-remote-config.js
 * One-shot script: merges key=true flags into Firebase Remote Config.
 * Run with: node set-remote-config.js
 */
"use strict";

const admin = require("firebase-admin");

if (!admin.apps.length) {
  admin.initializeApp({
    projectId: "amen-5e359",
  });
}

const UPDATES = {
  connect_hub_enabled:    { defaultValue: { value: "true" } },
  connect_you_menu_enabled: { defaultValue: { value: "true" } },
  discussion_modes_enabled: { defaultValue: { value: "true" } },
  context_participation_enabled: { defaultValue: { value: "true" } },
  discussion_health_enabled: { defaultValue: { value: "true" } },
  draft_intelligence_enabled: { defaultValue: { value: "true" } },
  discussion_summary_enabled: { defaultValue: { value: "true" } },
  discussion_mediator_enabled: { defaultValue: { value: "true" } },
  community_memory_enabled: { defaultValue: { value: "true" } },
  discussion_actions_enabled: { defaultValue: { value: "true" } },
  participation_tiers_enabled: { defaultValue: { value: "true" } },
  discussion_command_center_enabled: { defaultValue: { value: "true" } },
  community_os_enabled: { defaultValue: { value: "true" } },
  community_os_discussion_enabled: { defaultValue: { value: "true" } },
  community_os_prayer_os_enabled: { defaultValue: { value: "true" } },
  berean_os_projects_enabled: { defaultValue: { value: "true" } },
  berean_os_research_engine_enabled: { defaultValue: { value: "true" } },
  berean_os_wisdom_engine_enabled: { defaultValue: { value: "true" } },
  berean_os_multi_perspective_enabled: { defaultValue: { value: "true" } },
  berean_os_debate_engine_enabled: { defaultValue: { value: "true" } },
  berean_os_social_knowledge_feed_enabled: { defaultValue: { value: "true" } },
  berean_os_advisory_boards_enabled: { defaultValue: { value: "true" } },
  berean_os_mentor_os_enabled: { defaultValue: { value: "true" } },
  berean_os_knowledge_graph_enabled: { defaultValue: { value: "true" } },
  berean_os_onboarding_enabled: { defaultValue: { value: "true" } },
  berean_os_memory_brain_enabled: { defaultValue: { value: "true" } },
  berean_os_action_planner_enabled: { defaultValue: { value: "true" } },
  berean_os_truth_labels_enabled: { defaultValue: { value: "true" } },
  berean_os_source_explorer_enabled: { defaultValue: { value: "true" } },
  berean_os_social_projects_enabled: { defaultValue: { value: "true" } },
  berean_os_community_intelligence_enabled: { defaultValue: { value: "true" } },
  berean_os_living_documents_enabled: { defaultValue: { value: "true" } },
  community_os_action_pill_enabled: { defaultValue: { value: "true" } },
  community_os_universal_composer_enabled: { defaultValue: { value: "true" } },
  community_os_church_os_enabled: { defaultValue: { value: "true" } },
  community_os_org_os_enabled: { defaultValue: { value: "true" } },
  community_os_opportunity_enabled: { defaultValue: { value: "true" } },
};

(async () => {
  const rc = admin.remoteConfig();

  // Fetch current template
  let template;
  try {
    template = await rc.getTemplate();
    console.log(`Fetched template (version ${template.version?.versionNumber})`);
  } catch (err) {
    console.error("getTemplate failed:", err.message);
    process.exit(1);
  }

  // Merge updates
  for (const [key, value] of Object.entries(UPDATES)) {
    template.parameters[key] = {
      ...(template.parameters[key] || {}),
      ...value,
    };
    console.log(`  SET ${key} = true`);
  }

  // Publish
  try {
    const updated = await rc.publishTemplate(template);
    console.log(`\nPublished. New version: ${updated.version?.versionNumber}`);
  } catch (err) {
    console.error("publishTemplate failed:", err.message);
    process.exit(1);
  }
})();
