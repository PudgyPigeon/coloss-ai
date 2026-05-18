#!/usr/bin/env bash
# Aligned with the hierarchical values directory layout: mgmt/, infra/, apps/
set -euo pipefail

echo "=================================================="
echo " 🏗️  Renderer: Hydrating & templating Helm charts"
echo "=================================================="

# Loop through each tier and its path
for tier_entry in $TIER_MAPPINGS; do
    tier_name=$(echo "$tier_entry" | cut -d: -f1)
    tier_path=$(echo "$tier_entry" | cut -d: -f2)

    if [ -d "$tier_path" ]; then
        echo "➡️  Processing Tier: $tier_name"
        for component_path in "$tier_path"/*; do
            if [ -d "$component_path" ] && [ -f "$component_path/Chart.yaml" ]; then
                name=$(basename "$component_path")
                RENDER_TMP=$(mktemp -d)
                
                # Make sure we clean up even if step fails
                trap 'rm -rf "$RENDER_TMP"' EXIT

                # 1. Base values.yaml (Low Priority)
                VALS_ARGS=""
                if [ -f "$component_path/values.yaml" ]; then
                    VALS_ARGS="-f $component_path/values.yaml"
                fi

                # 2. Environment/Tier values.yaml (High Priority)
                # Aligns perfectly with nested path: e.g. values/sandbox/apps/don-erleone.yaml
                ENV_VALS="$ENV_VALUES_DIR/$tier_name/$name.yaml"
                if [ -f "$ENV_VALS" ]; then
                    VALS_ARGS="$VALS_ARGS -f $ENV_VALS"
                    echo "   ❇️  Found tier override: $tier_name/$name.yaml"
                fi

                echo "   📦 Templating: $name..."
                
                # Render the Helm chart
                helm template "$name" "$component_path" \
                    $VALS_ARGS \
                    --namespace "$name" \
                    --output-dir "$RENDER_TMP"

                # Move files to output directory
                mkdir -p "$out/$tier_name/$name"
                find "$RENDER_TMP" -name "*.yaml" -exec cp {} "$out/$tier_name/$name/" \;
                
                # Manual cleanup of temp directory
                rm -rf "$RENDER_TMP"
                trap - EXIT
            fi
        done
    fi
done

# Validate output
if [ -z "$(find "$out" -name "*.yaml" -print -quit)" ]; then
    echo "❌ ERROR: No manifests were rendered."
    exit 1
fi

echo "=================================================="
echo " ✅ Render complete: Manifests populated successfully."
echo "=================================================="
