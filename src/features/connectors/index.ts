/**
 * index.ts — public surface of the Connectors Hub (Connected Intelligence v1).
 * OWNER: Phase 2 Agent A.
 *
 * Mount `<ConnectorsHubScreen/>` from here. Other Connected Intelligence surfaces
 * import the reusable `DegradedChip` / `CapChip` to render connector error/cap
 * states consistently.
 */

export { default as ConnectorsHubScreen } from './ConnectorsHubScreen';
export type { ConnectorsHubScreenProps } from './ConnectorsHubScreen';

export { default as UsageLimitsScreen } from './UsageLimitsScreen';
export type { UsageLimitsScreenProps } from './UsageLimitsScreen';

export { default as MinorExplainer } from './MinorExplainer';

// Reusable status chips — imported by other Connected Intelligence surfaces.
export { DegradedChip, CapChip, ConnectedChip, IdleChip } from './StatusChips';

// Provider layer.
export {
  getConnectorProvider,
  fetchConnectorStatuses,
  CalendarProvider,
  MusicProvider,
} from './ConnectorProvider';
export type {
  ConnectorProvider,
  ConnectorRuntimeStatus,
  GrantParams,
  UpdateGrantParams,
} from './ConnectorProvider';

// Metadata (plain-language copy) for reuse in onboarding / disclosures.
export { CONNECTOR_META, SCOPE_LABELS, SURFACE_LABELS, ORDERED_CONNECTORS } from './connectorMeta';
export type { ConnectorMeta } from './connectorMeta';

// Native OAuth bridge — the platform `beginOAuth` + native-host detection. NEW
// connectors (calendar/music) run ASWebAuthenticationSession via the iOS host.
export {
  beginOAuth,
  isNativeOAuthBridgeAvailable,
  NativeBridgeUnavailableError,
  OAuthConfigError,
  OAuthFlowError,
} from './oauthBridge';
export type { OAuthBridgeResult } from './oauthBridge';
