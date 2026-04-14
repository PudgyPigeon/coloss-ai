# A 3-step cleanup that keeps your current work safe:
# 1. Remove specific old generations (older than 14 days)
nix-env --delete-generations 2d

# 2. Garbage collect everything that isn't currently used or linked
nix-store --gc

nix-collect-garbage -d

nix-env --delete-generations

# 3. Deduplicate the store to save physical disk space
nix-store --optimise