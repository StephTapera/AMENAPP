// integrations/integrationErrors.ts
// Typed error contracts for the AMEN Integrations Platform

export type AmenIntegrationErrorCode =
  | "auth-required"
  | "feature-disabled"
  | "provider-not-connected"
  | "provider-expired"
  | "provider-rate-limited"
  | "provider-timeout"
  | "provider-error"
  | "provider-scope-insufficient"
  | "oauth-state-expired"
  | "oauth-state-consumed"
  | "oauth-state-invalid"
  | "meeting-already-exists"
  | "meeting-not-found"
  | "gathering-not-found"
  | "permission-denied"
  | "org-admin-required"
  | "invalid-input"
  | "rate-limited"
  | "unknown";

export class AmenIntegrationError extends Error {
  constructor(
    public readonly code: AmenIntegrationErrorCode,
    message?: string
  ) {
    super(message ?? code);
    this.name = "AmenIntegrationError";
  }
}

export class AmenProviderError extends Error {
  constructor(
    public readonly code: AmenIntegrationErrorCode,
    public readonly providerStatusCode?: number,
    message?: string
  ) {
    super(message ?? code);
    this.name = "AmenProviderError";
  }
}

export function errorResponse(code: AmenIntegrationErrorCode): { errorCode: AmenIntegrationErrorCode } {
  return { errorCode: code };
}

export function mapProviderHttpError(statusCode: number): AmenIntegrationErrorCode {
  if (statusCode === 401 || statusCode === 403) return "provider-expired";
  if (statusCode === 429) return "provider-rate-limited";
  if (statusCode === 404) return "meeting-not-found";
  return "provider-error";
}
