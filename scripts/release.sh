#!/bin/bash

# Release script for Toss macOS app
# Creates and pushes a git tag to trigger the GitHub Actions release workflow

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get the repo name from git remote
REPO_URL=$(git remote get-url origin 2>/dev/null || echo "")
if [[ "$REPO_URL" == *"github.com"* ]]; then
    REPO_NAME=$(echo "$REPO_URL" | sed -E 's/.*github.com[:/]([^/]+\/[^/]+)(\.git)?$/\1/')
else
    REPO_NAME="your-repo/toss-mac-app"
fi

echo -e "${BLUE}🚀 Toss Release Script${NC}\n"

# Check if we're on main branch
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_BRANCH" != "main" ] && [ "$CURRENT_BRANCH" != "master" ]; then
    echo -e "${YELLOW}⚠️  Warning: You're on branch '$CURRENT_BRANCH', not main/master${NC}"
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Check for uncommitted changes
if ! git diff-index --quiet HEAD --; then
    echo -e "${YELLOW}⚠️  Warning: You have uncommitted changes${NC}"
    git status --short
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Get latest tag
LATEST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "none")
if [ "$LATEST_TAG" != "none" ]; then
    echo -e "Latest tag: ${GREEN}$LATEST_TAG${NC}"
else
    echo -e "No previous tags found"
fi

# Prompt for version
echo ""
read -p "Enter version number (e.g., 1.0.0): " VERSION

# Validate version format (semantic versioning)
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo -e "${RED}❌ Invalid version format. Use semantic versioning: X.Y.Z (e.g., 1.0.0)${NC}"
    exit 1
fi

# Create tag name
TAG_NAME="v$VERSION"

# Check if tag already exists
if git rev-parse "$TAG_NAME" >/dev/null 2>&1; then
    echo -e "${RED}❌ Tag $TAG_NAME already exists${NC}"
    exit 1
fi

# Confirm
echo ""
echo -e "${BLUE}Ready to create and push tag:${NC} ${GREEN}$TAG_NAME${NC}"
echo -e "This will trigger the GitHub Actions release workflow."
read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Cancelled${NC}"
    exit 0
fi

# Create tag
echo -e "\n${BLUE}Creating tag...${NC}"
git tag -a "$TAG_NAME" -m "Release $TAG_NAME"

# Push tag
echo -e "${BLUE}Pushing tag to remote...${NC}"
git push origin "$TAG_NAME"

# Success!
echo ""
echo -e "${GREEN}✅ Successfully created and pushed tag $TAG_NAME${NC}"
echo ""
echo -e "${BLUE}📦 Release workflow triggered:${NC}"
echo -e "   https://github.com/$REPO_NAME/actions"
echo ""
echo -e "${BLUE}🔗 Release will be available at:${NC}"
echo -e "   https://github.com/$REPO_NAME/releases/tag/$TAG_NAME"
echo ""
echo -e "${YELLOW}💡 Tip: Monitor the workflow at the Actions URL above${NC}"