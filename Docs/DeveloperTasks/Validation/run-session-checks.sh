#!/bin/sh
set -eu
cd "$(dirname "$0")/../../.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p .build/SessionChecks
for suite in AudienceSessionChecks IntegratedSessionChecks; do
  xcrun swiftc -parse-as-library -module-cache-path .build/SessionChecks/ModuleCache \
    TouchMarketingDemo/Shared/Models/*.swift \
    TouchMarketingDemo/Shared/MockData/*.swift \
    TouchMarketingDemo/Shared/State/*.swift \
    TouchMarketingDemo/Shared/Utilities/*.swift \
    TouchMarketingDemo/Shared/Analytics/AnalyticsData.swift \
    TouchMarketingDemo/Shared/Analytics/AnalyticsFixtures.swift \
    TouchMarketingDemo/Features/Audience/AudienceRuleDraft.swift \
    "Tests/$suite.swift" -o ".build/SessionChecks/$suite"
  ".build/SessionChecks/$suite"
done
