#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}🔧 Setting up .git/hooks/pre-push...${NC}"

# Get the Git root
REPO_ROOT=$(git rev-parse --show-toplevel)
HOOK_PATH="$REPO_ROOT/.git/hooks/pre-push"

# Check if the hook already exists
if [ -f "$HOOK_PATH" ]; then
    echo -e "${GREEN}✔ pre-push hook already exists at $HOOK_PATH. Skipping creation.${NC}"
    exit 0
fi

# Create the pre-push hook
cat > "$HOOK_PATH" <<'EOF'
#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Running SwiftLint check...${NC}"

cd "$(git rev-parse --show-toplevel)" || exit 1

if ! command -v swiftlint &> /dev/null; then
    echo -e "${RED}SwiftLint is not installed. Please install it first:${NC}"
    echo "brew install swiftlint"
    exit 1
fi

SWIFT_FILES=$(find . -name "*.swift" -not -path "*/.*" -not -path "*/Pods/*" -not -path "*/Carthage/*" -not -path "*/.build/*")

if [ -z "$SWIFT_FILES" ]; then
    echo -e "${YELLOW}No Swift files found to lint.${NC}"
    exit 0
fi

echo -e "${YELLOW}Found Swift files to check:${NC}"
echo "$SWIFT_FILES"
echo

echo -e "${YELLOW}Running SwiftLint...${NC}"
SWIFTLINT_OUTPUT=$(echo "$SWIFT_FILES" | xargs swiftlint lint --reporter xcode --strict 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}✓ SwiftLint check passed. No warnings or errors found!${NC}"
    exit 0
else
    echo -e "${RED}✗ SwiftLint found issues that must be fixed before pushing:${NC}"
    echo "$SWIFTLINT_OUTPUT"
    echo
    echo -e "${RED}Push has been blocked due to SwiftLint violations.${NC}"
    echo -e "${YELLOW}To bypass this check (not recommended), use:${NC} git push --no-verify"
    exit 1
fi
EOF

# Make it executable
chmod +x "$HOOK_PATH"

echo -e "${GREEN}✔ pre-push hook successfully created at $HOOK_PATH${NC}"
