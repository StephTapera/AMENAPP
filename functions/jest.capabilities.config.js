// jest.capabilities.config.js — Jest configuration for Capabilities v1 tests
// Run with: npx jest --config functions/jest.capabilities.config.js

module.exports = {
  preset: "ts-jest",
  testEnvironment: "node",
  rootDir: ".",
  testMatch: [
    "**/src/capabilities/**/*.test.ts",
  ],
  moduleFileExtensions: ["ts", "js", "json"],
  transform: {
    "^.+\\.ts$": ["ts-jest", {
      tsconfig: {
        target: "ES2022",
        module: "commonjs",
        moduleResolution: "node",
        esModuleInterop: true,
        skipLibCheck: true,
        strict: false,
        types: ["node", "jest"],
      },
    }],
  },
};
