"use strict";
// accessPassPreview.ts — Build privacy-shaped preview response
//
// Never includes tokenHash, member lists, private prayer content,
// or any sensitive user data in the preview response.
Object.defineProperty(exports, "__esModule", { value: true });
exports.buildPreviewResponse = buildPreviewResponse;
function buildPreviewResponse(pass, alreadyMember, existingRequestPending) {
    return {
        accessPassId: pass.accessPassId,
        targetType: pass.targetType,
        targetId: pass.targetId,
        title: pass.title,
        subtitle: pass.subtitle,
        description: pass.description,
        verifiedHostName: pass.verifiedHostName,
        verifiedHostBadge: pass.verifiedHostBadge ?? false,
        mode: pass.mode,
        requiredAction: pass.landingConfig.primaryActionLabel,
        communityRulesSummary: undefined, // Reserved for future community rules integration
        visibilityWarning: pass.safetyProfile.showMemberVisibilityWarning
            ? "Your display name and profile photo will be visible to group members."
            : undefined,
        privacyWarning: pass.safetyProfile.showPrayerPrivacyWarning
            ? "Prayer requests in this space are shared with group members. Treat them with care."
            : undefined,
        allowedActions: pass.landingConfig.allowedActions,
        requiresAuth: pass.requiresAuth,
        requiresApproval: pass.requiresApproval,
        alreadyMember,
        existingRequestPending,
    };
}
//# sourceMappingURL=accessPassPreview.js.map