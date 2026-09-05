#!/usr/bin/env bash
set -euo pipefail

echo "=================================================="
echo " 🔍 Scanning for Chart dependencies under: ${HELM_SOURCE_PATH}"
echo "=================================================="

# Find all directories containing a Chart.yaml
CHARTS=$(find "${HELM_SOURCE_PATH}" -name "Chart.yaml" -exec dirname {} \;)

for chart in $CHARTS; do
  echo "📦 Updating: $(basename "$chart") ($chart)"
  helm dependency build "$chart" --skip-refresh
done

echo "=================================================="
echo " ✅ Success: All Helm chart dependencies updated."
echo "=================================================="
