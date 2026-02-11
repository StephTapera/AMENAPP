#!/bin/bash
# Stabilization Pass Verification Script
# Run this after building to verify all fixes

echo "🔍 Stabilization Pass Verification"
echo "===================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check 1: Verify files were modified
echo "📝 Check 1: Verify modified files exist..."
files=(
    "NotificationsView.swift"
    "NotificationService.swift"
    "NotificationServiceExtensions.swift"
    "NotificationQuickActions.swift"
    "FollowRequestsView.swift"
)

for file in "${files[@]}"; do
    if [ -f "$file" ]; then
        echo -e "${GREEN}✅${NC} Found: $file"
    else
        echo -e "${RED}❌${NC} Missing: $file"
    fi
done

echo ""

# Check 2: Verify dangerous patterns are gone
echo "🔒 Check 2: Scan for dangerous patterns..."

echo -n "  Checking for 'as Void' casts... "
if grep -r "as Void" --include="*.swift" . > /dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  Found (review manually)${NC}"
else
    echo -e "${GREEN}✅ None found${NC}"
fi

echo -n "  Checking for force unwraps in Auth... "
if grep -r "Auth.auth().currentUser!.email" --include="*.swift" . > /dev/null 2>&1; then
    echo -e "${RED}❌ Found${NC}"
else
    echo -e "${GREEN}✅ None found${NC}"
fi

echo -n "  Checking for strong captures in Tasks... "
# This is approximate - manual review still needed
task_count=$(grep -r "Task {" --include="*.swift" . | wc -l)
weak_count=$(grep -r "Task.*\[weak" --include="*.swift" . | wc -l)
echo -e "${YELLOW}ℹ️  $task_count Tasks, $weak_count with weak capture${NC}"

echo ""

# Check 3: Look for our fixes
echo "🔧 Check 3: Verify fixes are in place..."

echo -n "  Username extraction with fallback... "
if grep -q "currentUser.displayName ?? \"Unknown\"" NotificationsView.swift; then
    echo -e "${GREEN}✅ Found${NC}"
else
    echo -e "${RED}❌ Not found${NC}"
fi

echo -n "  Navigation ID validation... "
if grep -q "!actorId.isEmpty" NotificationsView.swift; then
    echo -e "${GREEN}✅ Found${NC}"
else
    echo -e "${RED}❌ Not found${NC}"
fi

echo -n "  Retry count reset... "
if grep -q "retryCount = 0 // Reset retry count" NotificationService.swift; then
    echo -e "${GREEN}✅ Found${NC}"
else
    echo -e "${RED}❌ Not found${NC}"
fi

echo -n "  Comment count error handling... "
if grep -q "Failed to increment comment count" NotificationQuickActions.swift; then
    echo -e "${GREEN}✅ Found${NC}"
else
    echo -e "${RED}❌ Not found${NC}"
fi

echo -n "  TaskGroup for user fetching... "
if grep -q "withTaskGroup" FollowRequestsView.swift; then
    echo -e "${GREEN}✅ Found${NC}"
else
    echo -e "${RED}❌ Not found${NC}"
fi

echo -n "  Dead code removal (listenerRegistration)... "
if grep -q "listenerRegistration" NotificationServiceExtensions.swift; then
    echo -e "${RED}❌ Still present${NC}"
else
    echo -e "${GREEN}✅ Removed${NC}"
fi

echo ""

# Check 4: Count lines of code changed
echo "📊 Check 4: Code metrics..."
echo -e "${YELLOW}ℹ️  Run 'git diff --stat' to see detailed changes${NC}"

echo ""

# Check 5: Build check
echo "🏗️  Check 5: Build verification..."
echo -e "${YELLOW}⚠️  Manual step: Run 'xcodebuild' or build in Xcode${NC}"

echo ""

# Final summary
echo "================================"
echo "✅ Verification complete!"
echo ""
echo "Next steps:"
echo "1. Build in Xcode (Cmd+B)"
echo "2. Run Static Analyzer (Cmd+Shift+B)"
echo "3. Run manual tests from STABILIZATION_PASS_2026_02_05.md"
echo "4. Enable Thread Sanitizer and test"
echo ""
echo "See STABILIZATION_PASS_2026_02_05.md for full checklist."
