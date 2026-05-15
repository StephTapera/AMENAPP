// Mock for @anthropic-ai/sdk — not installed; selahMedia uses it at runtime only.
const Anthropic = jest.fn().mockImplementation(() => ({
    messages: {
        create: jest.fn().mockResolvedValue({ content: [{ text: "mock response" }] }),
    },
}));
module.exports = Anthropic;
module.exports.default = Anthropic;
