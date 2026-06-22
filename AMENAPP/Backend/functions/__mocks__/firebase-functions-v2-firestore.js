'use strict';
const onDocumentCreated = jest.fn((pattern, handler) => handler);
const onDocumentUpdated = jest.fn((pattern, handler) => handler);
const onDocumentDeleted = jest.fn((pattern, handler) => handler);
module.exports = { onDocumentCreated, onDocumentUpdated, onDocumentDeleted };
