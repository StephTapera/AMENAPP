module.exports = {
  env: {
    es2021: true,
    node: true,
  },
  parserOptions: {
    ecmaVersion: 2021,
    sourceType: "module",
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
    "indent": ["error", 2],
    "object-curly-spacing": ["error", "never"],
  },
};
