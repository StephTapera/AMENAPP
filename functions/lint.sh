#!/bin/bash
# Lint only JavaScript files in the current directory
cd "$(dirname "$0")"
npx eslint index.js pushNotifications.js aiModeration.js
