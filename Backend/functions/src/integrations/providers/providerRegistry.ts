import type {AmenIntegrationProvider, IntegrationProviderAdapter} from "../models";
import {MicrosoftGraphProvider} from "./MicrosoftGraphProvider";
import {SlackProvider} from "./SlackProvider";
import {ZoomProvider} from "./ZoomProvider";

export function getProviderAdapter(provider: AmenIntegrationProvider): IntegrationProviderAdapter {
    if (provider === "microsoft") {
        return new MicrosoftGraphProvider(
            process.env.MICROSOFT_GRAPH_CLIENT_ID ?? "",
            process.env.MICROSOFT_GRAPH_CLIENT_SECRET ?? ""
        );
    }
    if (provider === "zoom") {
        return new ZoomProvider(
            process.env.ZOOM_CLIENT_ID ?? "",
            process.env.ZOOM_CLIENT_SECRET ?? ""
        );
    }
    return new SlackProvider(
        process.env.SLACK_CLIENT_ID ?? "",
        process.env.SLACK_CLIENT_SECRET ?? ""
    );
}

export function assertProviderConfigured(provider: AmenIntegrationProvider): void {
    const required = provider === "microsoft"
        ? ["MICROSOFT_GRAPH_CLIENT_ID", "MICROSOFT_GRAPH_CLIENT_SECRET"]
        : provider === "zoom"
            ? ["ZOOM_CLIENT_ID", "ZOOM_CLIENT_SECRET"]
            : ["SLACK_CLIENT_ID", "SLACK_CLIENT_SECRET"];

    for (const key of required) {
        if (!process.env[key]) {
            throw new Error(`${provider}_provider_not_configured`);
        }
    }
}
