const serverTimestamp = jest.fn(() => ({ _type: "serverTimestamp" }));
const arrayUnion = jest.fn((...args) => ({ _type: "arrayUnion", args }));
const FieldValue = { serverTimestamp, arrayUnion };

const mockDocData = {};
const mockDoc = {
    get: jest.fn(() => Promise.resolve({ data: () => mockDoc.__data, exists: !!mockDoc.__data })),
    set: jest.fn(() => Promise.resolve()),
    update: jest.fn(() => Promise.resolve()),
    collection: jest.fn(() => mockCollection),
    __data: undefined,
};
const mockCollection = {
    doc: jest.fn(() => mockDoc),
    add: jest.fn(() => Promise.resolve({ id: "mock-id" })),
};
const mockFirestore = jest.fn(() => ({
    collection: jest.fn(() => mockCollection),
}));
mockFirestore.FieldValue = FieldValue;

const admin = {
    firestore: mockFirestore,
    initializeApp: jest.fn(),
};

admin.firestore.FieldValue = FieldValue;
module.exports = admin;
module.exports.__mockDoc = mockDoc;
module.exports.__mockCollection = mockCollection;
