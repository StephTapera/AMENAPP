/**
 * evaluationHarness.ts — Berean eval suite type contracts.
 *
 * Defines EvalTestCase for use by evalSuites/*.ts files.
 * Mirrors the EvalTest shape in functions/berean/evalFramework.ts
 * with the extended fields used by the Backend eval suites.
 */

export interface GradeResult {
    passed: boolean;
    score: number;
    reason?: string;
}

export interface EvalTestCase {
    id: string;
    category: string;
    riskLevel: "low" | "medium" | "high" | "critical";
    prompt?: string;
    systemContext?: string;
    expectedBehavior: string;
    grader: (response: any) => boolean | GradeResult;
    tags?: string[];
}
