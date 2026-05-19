import * as logger from "firebase-functions/logger";

export function logDiscoverTelemetry(event: string, data: Record<string, unknown>): void {
  logger.info(`[discover] ${event}`, data);
}
