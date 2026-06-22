const passthrough = jest.fn((_path, handler) => handler);

module.exports = {
    onDocumentCreated: passthrough,
    onDocumentDeleted: passthrough,
    onDocumentUpdated: passthrough,
};
