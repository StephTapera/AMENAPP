const HttpsError = class HttpsError extends Error {
    constructor(code, message) {
        super(message);
        this.code = code;
    }
};

const onCall = jest.fn((optionsOrHandler, maybeHandler) => (
    typeof optionsOrHandler === "function" ? optionsOrHandler : maybeHandler
));

module.exports = { HttpsError, onCall };
