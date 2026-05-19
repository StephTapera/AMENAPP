'use strict';
const Anthropic = jest.fn(() => ({
  messages: {
    create: jest.fn().mockResolvedValue({
      content: [{ type: 'text', text: 'Mock response' }],
      usage: { input_tokens: 10, output_tokens: 20 },
    }),
  },
}));
module.exports = Anthropic;
module.exports.default = Anthropic;
