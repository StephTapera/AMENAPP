#!/bin/zsh
# Retry the canonical AMEN build until it exits 0 (green), backing off for a
# clear window so a cold/incremental build is not starved by peer builds.
set -u
cd "/Users/stephtapera/Desktop/AMEN/AMENAPP copy" || exit 99

STAMP="$(date +%Y%m%d-%H%M%S)"
SUMMARY="deploy-logs/build-until-green-${STAMP}.summary.log"
MAX_ATTEMPTS=8

note() { printf "%s\n" "$1" | tee -a "$SUMMARY"; }

note "build-until-green started $(date) HEAD=$(git rev-parse --short HEAD)"

attempt=1
final_ec=99
while [ "$attempt" -le "$MAX_ATTEMPTS" ]; do
  # 1) Wait for a clear window: no other xcodebuild running. Up to ~25 min.
  waited=0
  while :; do
    n=$(pgrep -f "xcodebuild -scheme AMENAPP" | wc -l | tr -d ' ')
    if [ "$n" -eq 0 ]; then break; fi
    if [ "$waited" -ge 150 ]; then
      note "attempt $attempt: window never cleared after ~25m ($n peer builds); proceeding anyway"
      break
    fi
    sleep 10; waited=$((waited+1))
  done

  LOG="deploy-logs/build-until-green-${STAMP}.attempt${attempt}.log"
  note "attempt $attempt: launching xcodebuild $(date) -> $LOG"
  printf "# ACQUIRED by build-until-green (claude) attempt %s at %s — HEAD %s\n" \
    "$attempt" "$(date '+%H:%M')" "$(git rev-parse --short HEAD)" >> .build-lock

  xcodebuild -scheme AMENAPP -destination 'generic/platform=iOS' build \
    -clonedSourcePackagesDirPath ./SourcePackages.nosync \
    -derivedDataPath ./DerivedData.nosync > "$LOG" 2>&1
  ec=$?
  errs=$(grep -c "error:" "$LOG")
  succeeded=$(grep -c "BUILD SUCCEEDED" "$LOG")
  note "attempt $attempt: exit=$ec error:lines=$errs BUILD_SUCCEEDED_lines=$succeeded"
  printf "# Released by build-until-green (claude) attempt %s — exit=%s errors=%s succeeded=%s (%s)\n" \
    "$attempt" "$ec" "$errs" "$succeeded" "$LOG" >> .build-lock

  if [ "$ec" -eq 0 ]; then
    note "GREEN on attempt $attempt"
    final_ec=0
    break
  fi

  # If real compile errors, capture a sample for diagnosis and stop retrying
  # (retrying won't fix genuine errors).
  if [ "$errs" -gt 0 ]; then
    note "attempt $attempt: real compile errors present — sample:"
    grep "error:" "$LOG" | head -20 | tee -a "$SUMMARY"
    final_ec="$ec"
    break
  fi

  # Otherwise (killed/starved/exit 143/65 with no error lines): back off and retry.
  note "attempt $attempt: no error lines (likely starved/killed) — backing off 60s and retrying"
  final_ec="$ec"
  sleep 60
  attempt=$((attempt+1))
done

note "build-until-green finished $(date) final_ec=$final_ec attempts_used=$attempt"
echo "DONE final_ec=$final_ec summary=$SUMMARY"
