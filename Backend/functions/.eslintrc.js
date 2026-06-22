/** @type {import("eslint").Linter.Config} */
module.exports = {
  root: true,
  env: {
    node: true,
    es2022: true,
  },
  parser: "@typescript-eslint/parser",
  parserOptions: {
    ecmaVersion: 2022,
    sourceType: "module",
  },
  plugins: ["@typescript-eslint"],
  extends: [
    "eslint:recommended",
    "plugin:@typescript-eslint/recommended",
  ],
  rules: {
    // Firebase/Firestore code necessarily casts data() results.
    // These patterns are idiomatic in Cloud Functions — disable globally.
    "@typescript-eslint/no-explicit-any": "off",
    "@typescript-eslint/no-non-null-assertion": "off",

    // Unused variables are real dead code issues and should be caught.
    // Prefix with _ to intentionally suppress (args and vars).
    "@typescript-eslint/no-unused-vars": [
      "error",
      { argsIgnorePattern: "^_", varsIgnorePattern: "^_" },
    ],

    // do { } while (true) and while (true) are intentional Firestore
    // pagination patterns across this codebase.  Only flag conditionals.
    "no-constant-condition": ["error", { checkLoops: false }],

    // require() is used by test files to access CommonJS mock exports.
    // Handled per file-type via overrides below.
    "@typescript-eslint/no-require-imports": "off",
    "@typescript-eslint/no-var-requires": "off",
  },
  overrides: [
    {
      // Test files use require() to access __mock* handles exported via
      // module.exports by the firebase-admin mock.  Allow it in test scope.
      files: ["src/**/*.test.ts"],
      rules: {
        "@typescript-eslint/no-var-requires": "off",
        "@typescript-eslint/no-require-imports": "off",
        // Test helpers may be declared but only used conditionally — relax to warn.
        "@typescript-eslint/no-unused-vars": [
          "warn",
          { argsIgnorePattern: "^_", varsIgnorePattern: "^_" },
        ],
      },
    },
  ],
  ignorePatterns: [
    "lib/",
    "node_modules/",
    "__mocks__/",
    "*.js",
  ],
};
