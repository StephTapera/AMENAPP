const HttpsError = class HttpsError extends Error {
    constructor(code, message) {
        super(message);
        this.code = code;
    }
};

const onCall = jest.fn((handler) => handler);

module.exports = { HttpsError, onCall };
