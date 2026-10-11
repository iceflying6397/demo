#!/bin/sh
set -eu
cd "$(dirname "$0")/../../.."
mkdir -p .build/AnalyticsValidation
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
xcrun swiftc -module-cache-path .build/AnalyticsValidation/ModuleCache \
  TouchMarketingDemo/Shared/Models/*.swift \
  TouchMarketingDemo/Shared/State/ApprovalAllocationRules.swift \
  TouchMarketingDemo/Shared/Utilities/DemoFormat.swift \
  TouchMarketingDemo/Shared/MockData/MockDataStore.swift \
  TouchMarketingDemo/Shared/Analytics/*.swift \
  TouchMarketingDemo/Features/Analytics/AnalyticsSelection.swift \
  TouchMarketingDemo/Features/Analytics/AnalyticsChartData.swift \
  Docs/DeveloperTasks/AnalyticsValidation/main.swift \
  -o .build/AnalyticsValidation/analytics-checks
.build/AnalyticsValidation/analytics-checks
