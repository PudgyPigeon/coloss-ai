#!/usr/bin/env bash
set -e
echo "🔍 Searching for Helm charts in ${HELM_SOURCE_PATH} ..."

# Find all directories containing a Chart.yaml
CHARTS=$(find "${HELM_SOURCE_PATH}" -name "Chart.yaml" -exec dirname {} \;)

for chart in $CHARTS; do
  echo "--------------------------------------------------"
  echo "📦 Updating dependencies for: $chart"
  helm dependency build "$chart"
done

echo "--------------------------------------------------"
echo "✅ All Helm dependencies are up to date."
