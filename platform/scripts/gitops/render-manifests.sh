#!/usr/bin/env bash
set -euo pipefail

# This script is called by Nix during the build phase to render Helm charts.
# Variables like $tiers, $envValuesDir, and $out are provided by the Nix environment.

# Create output directories for each tier
for tier in $TIER_NAMES; do
  mkdir -p "$out/$tier"
done

# Loop through each tier and its path
# Note: In the Nix-to-Bash handoff, we'll pass these as JSON or a simple string
for tier_entry in $TIER_MAPPINGS; do
    # format: "name:path"
    tier_name=$(echo "$tier_entry" | cut -d: -f1)
    tier_path=$(echo "$tier_entry" | cut -d: -f2)

    echo "--- Rendering Tier: $tier_name ---"
    if [ -d "$tier_path" ]; then
        for component_path in "$tier_path"/*; do
            if [ -d "$component_path" ] && [ -f "$component_path/Chart.yaml" ]; then
                name=$(basename "$component_path")
                RENDER_TMP=$(mktemp -d)

                # 1. Start empty
                VALS_ARG=""

                # 2. Add the base chart values (Lower Priority)
                BASE_VALS="$component_path/values.yaml"
                if [ -f "$BASE_VALS" ]; then
                    VALS_ARG="-f $BASE_VALS"
                fi

                # 3. Add the environment-specific values (Higher Priority)
                ENV_VALS="$ENV_VALUES_DIR/$name.yaml"
                if [ -f "$ENV_VALS" ]; then
                    VALS_ARG="$VALS_ARG -f $ENV_VALS"
                fi

                echo "Rendering $name into namespace $name..."

                # Execute Helm template
                helm template "$name" "$component_path" \
                    $VALS_ARG \
                    --namespace "$name" \
                    --output-dir "$RENDER_TMP"

                mkdir -p "$out/$tier_name/$name"
                find "$RENDER_TMP" -name "*.yaml" -exec cp {} "$out/$tier_name/$name/" \;
                rm -rf "$RENDER_TMP"
            fi
        done
    fi
done

if [ -z "$(find "$out" -name "*.yaml" -print -quit)" ]; then
    echo "❌ ERROR: No manifests were rendered."
    exit 1
fi
