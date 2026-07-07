#!/bin/bash

# simple-test-parser.sh
# Simple and effective test result parser for .xcresult bundles
# Usage: ./scripts/simple-test-parser.sh <path-to.xcresult>

set -e

XCRESULT_PATH="${1:-$(find ./build -name "*.xcresult" -type d 2>/dev/null | sort -r | head -1)}"

if [[ -z "$XCRESULT_PATH" ]] || [[ ! -d "$XCRESULT_PATH" ]]; then
    echo "❌ No .xcresult bundle found."
    echo "Usage: $0 <path-to.xcresult>"
    exit 1
fi

echo "📊 Test Results Analysis: $(basename "$XCRESULT_PATH")"
echo "=========================================================="

# Get the JSON data
TEMP_JSON=$(mktemp)
if ! xcrun xcresulttool get object --legacy --path "$XCRESULT_PATH" --format json > "$TEMP_JSON" 2>/dev/null; then
    echo "❌ Could not extract JSON from .xcresult bundle"
    rm -f "$TEMP_JSON"
    exit 1
fi

echo ""
echo "🚨 Test Failure Analysis:"
echo "--------------------------"

# Extract test failure summaries using jq if available
if command -v jq >/dev/null 2>&1; then
    FAILURE_COUNT=$(jq -r '.actions._values[].actionResult.issues.testFailureSummaries._values | length' "$TEMP_JSON" 2>/dev/null || echo "0")
    
    if [[ "$FAILURE_COUNT" -gt 0 ]]; then
        echo "Found $FAILURE_COUNT test failure(s):"
        echo ""
        
        jq -r '
            .actions._values[]?.actionResult.issues.testFailureSummaries._values[]? |
            "❌ Test: \(.testCaseName._value // "Unknown test")
            📍 Location: \(.documentLocationInCreatingWorkspace.url._value // "Unknown location" | gsub(".*file://|#.*$"; "") | gsub(".*/"; ""))
            💬 Message: \(.message._value // "No message")
            "
        ' "$TEMP_JSON" 2>/dev/null
        
    else
        echo "✅ No test failures found in testFailureSummaries"
    fi
    
    echo ""
    echo "📈 Overall Test Summary:"
    echo "------------------------"
    
    # Try to get test metrics
    METRICS=$(jq -r '.actions._values[]?.actionResult.metrics' "$TEMP_JSON" 2>/dev/null)
    if [[ "$METRICS" != "null" ]] && [[ -n "$METRICS" ]]; then
        jq -r '
            .actions._values[]?.actionResult.metrics |
            if . then
                "Tests Run: \(.testsCount._value // "Unknown")
                Failures: \(.testsFailedCount._value // "0") 
                Duration: \(.testsRealRunDuration._value // "Unknown")s"
            else
                "Metrics not available"
            end
        ' "$TEMP_JSON" 2>/dev/null || echo "Could not parse metrics"
    else
        echo "Test metrics not available in this format"
    fi
    
else
    echo "jq not available - using basic parsing..."
    
    # Basic grep-based parsing for key information
    echo "Failed Tests:"
    grep -o '"testCaseName":{"_value":"[^"]*"}' "$TEMP_JSON" 2>/dev/null | \
        sed 's/"testCaseName":{"_value":"\([^"]*\)"}/❌ \1/' || echo "No test case names found"
        
    echo ""
    echo "Failure Messages:"
    grep -o '"message":{"_value":"[^"]*"}' "$TEMP_JSON" 2>/dev/null | \
        sed 's/"message":{"_value":"\([^"]*\)"}/💬 \1/' | head -10 || echo "No failure messages found"
fi

echo ""
echo "💡 Quick Actions:"
echo "  Open in Xcode: open '$XCRESULT_PATH'"
echo "  View JSON: xcrun xcresulttool get object --legacy --path '$XCRESULT_PATH' --format json | jq ."

# Cleanup
rm -f "$TEMP_JSON"