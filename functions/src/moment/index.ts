import { configureMomentDeepenDependencies } from "./deepen/shared";
import { createMomentDeepenDependencies } from "./deepen/dependencies";

configureMomentDeepenDependencies(createMomentDeepenDependencies() as unknown as Record<string, unknown>);

export { momentSummarize } from "./deepen/summarize";
export { momentCrossReference } from "./deepen/crossReference";
export { momentGeneratePrayer } from "./deepen/generatePrayer";
export { momentGenerateStudyGuide } from "./deepen/generateStudyGuide";
export { momentGenerateDiscussion } from "./deepen/generateDiscussion";
export { momentGenerateDevotional } from "./deepen/generateDevotional";
export { momentSaveTo } from "./deepen/saveTo";

export { momentPrayLive } from "./gather/prayLive";
export { momentJoinAudio } from "./gather/joinAudio";
export { momentJoinDiscussion } from "./gather/joinDiscussion";
