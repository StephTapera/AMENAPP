'use strict';
const onSchedule = jest.fn((options, handler) => handler);
module.exports = { onSchedule };
