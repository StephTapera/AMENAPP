const serverTimestamp = jest.fn(() => ({ _type: "serverTimestamp" }));
const arrayUnion = jest.fn((...args) => ({ _type: "arrayUnion", args }));
const FieldValue = { serverTimestamp, arrayUnion };
const Timestamp = {
    now: jest.fn(() => {
        const millis = Date.now();
        return {
            seconds: Math.floor(millis / 1000),
            nanoseconds: (millis % 1000) * 1_000_000,
            toMillis: () => millis,
            toDate: () => new Date(millis),
        };
    }),
    fromDate: jest.fn((date) => {
        const millis = date.getTime();
        return {
            seconds: Math.floor(millis / 1000),
            nanoseconds: (millis % 1000) * 1_000_000,
            toMillis: () => millis,
            toDate: () => date,
        };
    }),
    fromMillis: jest.fn((millis) => ({
        seconds: Math.floor(millis / 1000),
        nanoseconds: (millis % 1000) * 1_000_000,
        toMillis: () => millis,
        toDate: () => new Date(millis),
    })),
};

const mockDocData = {};
const mockDoc = {
    get: jest.fn(() => Promise.resolve({ data: () => mockDoc.__data, exists: !!mockDoc.__data })),
    set: jest.fn(() => Promise.resolve()),
    update: jest.fn(() => Promise.resolve()),
    collection: jest.fn(() => mockCollection),
    __data: undefined,
};
const mockBatch = {
    commit: jest.fn(() => Promise.resolve()),
    set: jest.fn(),
    delete: jest.fn(),
};
const mockQuery = {
    orderBy: jest.fn(() => mockQuery),
    where: jest.fn(() => mockQuery),
    limit: jest.fn(() => mockQuery),
    get: jest.fn(() => Promise.resolve({ docs: [], empty: true })),
};
const mockCollection = {
    doc: jest.fn(() => mockDoc),
    add: jest.fn(() => Promise.resolve({ id: "mock-id" })),
    orderBy: jest.fn(() => mockQuery),
    where: jest.fn(() => mockQuery),
    limit: jest.fn(() => mockQuery),
    get: jest.fn(() => Promise.resolve({ docs: [], empty: true })),
};
const mockFirestore = jest.fn(() => ({
    collection: jest.fn(() => mockCollection),
    batch: jest.fn(() => mockBatch),
}));
mockFirestore.FieldValue = FieldValue;
mockFirestore.Timestamp = Timestamp;

const admin = {
    firestore: mockFirestore,
    initializeApp: jest.fn(),
};

admin.firestore.FieldValue = FieldValue;
admin.firestore.Timestamp = Timestamp;
module.exports = admin;
module.exports.__mockDoc = mockDoc;
module.exports.__mockCollection = mockCollection;
module.exports.__mockBatch = mockBatch;
module.exports.__mockQuery = mockQuery;
