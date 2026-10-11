#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$repo"
mkdir -p .build/PlanChecks
xcrun swiftc -parse-as-library \
  TouchMarketingDemo/Shared/Utilities/DemoFormat.swift \
  TouchMarketingDemo/Shared/Models/Audience.swift \
  TouchMarketingDemo/Shared/Models/MarketingPlan.swift \
  TouchMarketingDemo/Shared/Models/ApprovalTask.swift \
  TouchMarketingDemo/Shared/Models/ApprovalDelivery.swift \
  TouchMarketingDemo/Shared/State/ApprovalAllocationRules.swift \
  TouchMarketingDemo/Shared/Models/AnalyticsSummary.swift \
  TouchMarketingDemo/Shared/Models/PlanDomain.swift \
  TouchMarketingDemo/Shared/Models/PlanValidation.swift \
  TouchMarketingDemo/Shared/MockData/MockDataStore.swift \
  TouchMarketingDemo/Shared/MockData/MockDataStore+Plan.swift \
  Docs/DeveloperTasks/Validation/PlanDomainChecks.swift \
  -o .build/PlanChecks/checks
.build/PlanChecks/checks
