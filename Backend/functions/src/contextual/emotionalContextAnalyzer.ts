import { spiritualStateEngine } from "../berean/services/SpiritualStateEngine";
import type { BereanContextPayload } from "./bereanSelectionActions";

export interface EmotionalContextSummary {
  primaryState: string;
  sensitivityFlags: string[];
  responseMode: string;
  leadershipEscalationRecommended: boolean;
  crisisSupportRecommended: boolean;
}

export function analyzeEmotionalContext(payload: BereanContextPayload): EmotionalContextSummary {
  const classification = spiritualStateEngine.classify(payload.selectedText);

  return {
    primaryState: classification.primaryState,
    sensitivityFlags: classification.sensitivityFlags ?? [],
    responseMode: classification.selectedResponseMode,
    leadershipEscalationRecommended: classification.escalationTriggered,
    crisisSupportRecommended: classification.signals.crisisSignalDetected,
  };
}
