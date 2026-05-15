const defineSecret = jest.fn((name) => ({
    name,
    value: jest.fn(() => `mock-${name}-value`),
}));

module.exports = { defineSecret };
