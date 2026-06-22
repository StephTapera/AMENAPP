// index.ts — Find a Church v2 module exports (callables, us-east1).
//
// Wired into the root functions/index.js via `require("./lib/church")` after
// `npm run build:church`. Deploy per-function only (never bare):
//   firebase deploy --only functions:assembleChurchDiscovery
//   firebase deploy --only functions:searchChurches
//   firebase deploy --only functions:getChurchProfile
//   firebase deploy --only functions:toggleSavedChurch
//   firebase deploy --only functions:recordChurchSearch
//   firebase deploy --only functions:planVisit
//   firebase deploy --only functions:reportChurch
//   firebase deploy --only functions:requestChurchVerification
//   firebase deploy --only functions:submitChurchClaim

export {
  assembleChurchDiscovery,
  searchChurches,
  getChurchProfile,
  toggleSavedChurch,
  recordChurchSearch,
  planVisit,
  reportChurch,
  requestChurchVerification,
  submitChurchClaim,
} from "./callable";
