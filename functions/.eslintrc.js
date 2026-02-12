module.exports = {
  env: {
    es2021: true,
    node: true,
  },
  parserOptions: {
    ecmaVersion: 2021,
  },
  extends: [
    "eslint:recommended",
    "google",
  ],
  rules: {
    "quotes": ["error", "double"],
    "max-len": ["error", {"code": 120}],
    "require-jsdoc": "off",
    "valid-jsdoc": "off",
  },
  ignorePatterns: [
    "node_modules/",
    "../**/*",
    "**/*.swift",
    "**/*.md",
  ],
};
