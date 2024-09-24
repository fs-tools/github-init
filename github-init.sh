#!/bin/bash

# github-init
# A script to create and manage GitHub repositories, initialize local Git repositories,
# and link them together with customizable options, including repository name specification.

# Exit immediately if a command exits with a non-zero status
set -e

# -------------------- #
#    Color Definitions #
# -------------------- #

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# -------------------- #
#    Default Settings   #
# -------------------- #

DEFAULT_ORG="fs-tools"
DEFAULT_PATH="$(pwd)"
ORG_NAME="$DEFAULT_ORG"
TARGET_PATH="$DEFAULT_PATH"
REPO_NAME=""
PROJECT_NAME=""
VERBOSE=false
GITHUB_TOKEN=""
SETTINGS_FILE="$HOME/.github-initrc"
GITHUB_API="https://api.github.com"

# -------------------- #
#      Usage Function    #
# -------------------- #

usage() {
    echo -e "${YELLOW}Usage:${NC} github-init [options] [<projectName>]"
    echo ""
    echo "Options:"
    echo "  -h, --help                Show this help message and exit"
    echo "  -o, --org <orgName>       Specify the GitHub organization (overrides config)"
    echo "  -r, --repo <repoName>     Specify the GitHub repository name"
    echo "  -v, --verbose             Enable verbose output"
    echo ""
    echo "Examples:"
    echo "  github-init"
    echo "  github-init -o fs-random -r api-interceptor"
    echo "  github-init --org fs-random --repo api-interceptor --verbose"
    echo "  github-init -r api-interceptor"
    exit 1
}

# -------------------- #
#   Argument Parsing    #
# -------------------- #

# Function for verbose logging
log() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${BLUE}==>${NC} $1"
    fi
}

# Function to sanitize repository name
sanitize_repo_name() {
    local input="$1"
    # Convert to lowercase
    local sanitized
    sanitized=$(echo "$input" | tr '[:upper:]' '[:lower:]')
    # Replace any non-alphanumeric character with a dash
    sanitized=$(echo "$sanitized" | tr -c 'a-z0-9' '-')
    # Replace multiple consecutive dashes with a single dash
    sanitized=$(echo "$sanitized" | tr -s '-')
    # Remove leading and trailing dashes
    sanitized=$(echo "$sanitized" | sed 's/^[-]*//;s/[-]*$//')
    echo "$sanitized"
}

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        -o|--org)
            if [[ -n "$2" && ! "$2" =~ ^- ]]; then
                ORG_NAME="$2"
                shift
            else
                echo -e "${RED}Error:${NC} --org requires a non-empty option argument."
                exit 1
            fi
            ;;
        -r|--repo)
            if [[ -n "$2" && ! "$2" =~ ^- ]]; then
                REPO_NAME="$2"
                shift
            else
                echo -e "${RED}Error:${NC} --repo requires a non-empty option argument."
                exit 1
            fi
            ;;
        -v|--verbose)
            VERBOSE=true
            ;;
        -*)
            echo -e "${RED}Error:${NC} Unknown option: $1"
            usage
            ;;
        *)
            if [ -z "$PROJECT_NAME" ]; then
                PROJECT_NAME="$1"
            else
                echo -e "${RED}Error:${NC} Multiple project names provided. Please specify only one."
                usage
            fi
            ;;
    esac
    shift
done

# -------------------- #
#    Dependency Checks  #
# -------------------- #

# Check for Git
if ! command -v git &> /dev/null; then
    echo -e "${RED}Error:${NC} Git is not installed. Please install Git and try again."
    exit 1
fi

# Check for cURL
if ! command -v curl &> /dev/null; then
    echo -e "${RED}Error:${NC} cURL is not installed. Please install cURL and try again."
    exit 1
fi

# Check for jq
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error:${NC} jq is not installed. Please install jq and try again."
    exit 1
fi

# -------------------- #
#   Configuration Setup  #
# -------------------- #

# Function to initialize settings file with default values
initialize_settings() {
    echo -e "${YELLOW}Initializing configuration file with default settings...${NC}"
    {
        printf 'ORG_NAME="%s"\n' "$DEFAULT_ORG"
        printf 'TARGET_PATH="%s"\n' "$DEFAULT_PATH"
        printf 'VERBOSE="%s"\n' "false"
        printf 'GITHUB_TOKEN=""\n'
    } > "$SETTINGS_FILE"
    chmod 600 "$SETTINGS_FILE"  # Restrict permissions
}

# Function to load settings
load_settings() {
    if [ -f "$SETTINGS_FILE" ]; then
        # Source the settings file to load variables
        source "$SETTINGS_FILE"
    else
        initialize_settings
    fi
}

# Function to save settings
save_settings() {
    # Use printf to handle any special characters in the token
    {
        printf 'ORG_NAME="%s"\n' "$ORG_NAME"
        printf 'TARGET_PATH="%s"\n' "$TARGET_PATH"
        printf 'VERBOSE="%s"\n' "$VERBOSE"
        printf 'GITHUB_TOKEN="%s"\n' "$GITHUB_TOKEN"
    } > "$SETTINGS_FILE"
}

# Load existing settings
load_settings

# Prompt for GitHub Token if not set
if [ -z "$GITHUB_TOKEN" ]; then
    echo -e "${YELLOW}GitHub token not found.${NC}"
    read -s -p "Please enter your GitHub Personal Access Token: " input_token
    echo
    # Validate the token by making a simple API call
    RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: token $input_token" "$GITHUB_API/user")
    if [ "$RESPONSE" -ne 200 ]; then
        echo -e "${RED}Error:${NC} Invalid GitHub token. Please check and try again."
        exit 1
    fi
    GITHUB_TOKEN="$input_token"
    save_settings
    echo -e "${GREEN}GitHub token saved successfully in ${SETTINGS_FILE}.${NC}"
fi

# -------------------- #
#    Repository Name Setup #
# -------------------- #

# Determine the repository name
if [ -n "$REPO_NAME" ]; then
    PROJECT_NAME=$(sanitize_repo_name "$REPO_NAME")
    log "Repository name provided via option: $PROJECT_NAME"
elif [ -n "$PROJECT_NAME" ]; then
    PROJECT_NAME=$(sanitize_repo_name "$PROJECT_NAME")
    log "Repository name provided as positional argument: $PROJECT_NAME"
else
    # Use the current directory's name as the repository name
    PROJECT_NAME=$(sanitize_repo_name "$(basename "$(pwd)")")
    log "No repository name provided. Using current directory name: $PROJECT_NAME"
fi

# Ensure the repository name adheres to the naming conventions
if [[ ! "$PROJECT_NAME" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
    echo -e "${RED}Error:${NC} Invalid repository name '${PROJECT_NAME}'. Ensure it's all lowercase, uses single dashes instead of spaces or special characters, and does not contain multiple consecutive dashes."
    exit 1
fi

# -------------------- #
#    Directory Handling  #
# -------------------- #

prepare_directory() {
    log "Navigating to target directory: $TARGET_PATH"
    cd "$TARGET_PATH"

    echo -e "${GREEN}Repository Name: ${PROJECT_NAME}${NC}"
}

# -------------------- #
#    Preview of Actions  #
# -------------------- #

preview_actions() {
    echo -e "${GREEN}========== Preview of Actions ==========${NC}"
    echo -e "${YELLOW}- GitHub Repository:${NC} https://github.com/${ORG_NAME}/${PROJECT_NAME}"
    echo -e "${YELLOW}- Local Directory:${NC} $(pwd)"
    
    if [ -d ".git" ]; then
        echo -e "${YELLOW}- Local Git Repository:${NC} Already initialized."
    else
        echo -e "${YELLOW}- Local Git Repository:${NC} Will be initialized."
    fi

    echo -e "${YELLOW}- .gitignore File:${NC} Will be created if not present."
    echo -e "${YELLOW}- Initial Commit:${NC} Will be made with message 'init'."
    echo -e "${YELLOW}- Remote Origin:${NC} Will be set to https://github.com/${ORG_NAME}/${PROJECT_NAME}.git"
    echo -e "${GREEN}=========================================${NC}"
}

# -------------------- #
#       Confirmation     #
# -------------------- #

confirm() {
    read -p "Do you want to proceed? [y/N]: " choice
    case "$choice" in 
        y|Y ) echo "Proceeding...";;
        * ) echo "Operation cancelled."; exit 0;;
    esac
}

# -------------------- #
#  Create GitHub Repo    #
# -------------------- #

create_github_repo() {
    log "Creating GitHub repository..."

    # Check if repository already exists
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: token $GITHUB_TOKEN" \
        "$GITHUB_API/repos/$ORG_NAME/$PROJECT_NAME")

    if [ "$HTTP_STATUS" -eq 200 ]; then
        echo -e "${YELLOW}Warning:${NC} Repository https://github.com/${ORG_NAME}/${PROJECT_NAME} already exists."
    elif [ "$HTTP_STATUS" -eq 404 ]; then
        # Create the repository
        RESPONSE=$(curl -s -w "\n%{http_code}" \
            -H "Authorization: token $GITHUB_TOKEN" \
            -H "Accept: application/vnd.github.v3+json" \
            -X POST "$GITHUB_API/orgs/$ORG_NAME/repos" \
            -d "{\"name\":\"$PROJECT_NAME\", \"private\":false}")

        BODY=$(echo "$RESPONSE" | sed '$d')
        HTTP_CODE=$(echo "$RESPONSE" | tail -n1)

        if [ "$HTTP_CODE" -eq 201 ]; then
            echo -e "${GREEN}Success:${NC} GitHub repository created at https://github.com/${ORG_NAME}/${PROJECT_NAME}"
        elif [ "$HTTP_CODE" -eq 422 ]; then
            echo -e "${RED}Error:${NC} Repository already exists or validation failed."
            echo "$BODY" | grep -i "errors" && exit 1
        else
            echo -e "${RED}Error:${NC} Failed to create repository. HTTP Status: $HTTP_CODE"
            echo "$BODY"
            exit 1
        fi
    else
        echo -e "${RED}Error:${NC} Failed to check repository status. HTTP Status: $HTTP_STATUS"
        exit 1
    fi
}

# -------------------- #
#   Initialize Git Repo  #
# -------------------- #

initialize_git_repo() {
    if [ -d ".git" ]; then
        log "Git repository already initialized. Skipping git init."
    else
        log "Initializing Git repository..."
        git init
        echo -e "${GREEN}Git repository initialized.${NC}"
    fi
}

# -------------------- #
#      Create .gitignore  #
# -------------------- #

create_gitignore() {
    GITIGNORE_FILE=".gitignore"
    if [ -f "$GITIGNORE_FILE" ]; then
        echo -e "${YELLOW}Notice:${NC} .gitignore already exists. Skipping creation."
    else
        echo -e "${GREEN}Creating .gitignore file...${NC}"
        cat <<EOL > "$GITIGNORE_FILE"
node_modules
.yarn.*
EOL
        echo -e "${GREEN}.gitignore created with default contents.${NC}"
    fi
}

# -------------------- #
#    Make Initial Commit #
# -------------------- #

make_initial_commit() {
    log "Staging files for initial commit..."
    git add .

    # Check if there are any changes to commit
    if git diff --cached --quiet; then
        echo -e "${YELLOW}Notice:${NC} No changes to commit."
    else
        log "Creating initial commit..."
        git commit -m "init"
        echo -e "${GREEN}Initial commit created with message 'init'.${NC}"
    fi
}

# -------------------- #
#      Push Repository   #
# -------------------- #

push_repository() {
    REMOTE_URL="https://github.com/${ORG_NAME}/${PROJECT_NAME}.git"

    # Check if remote 'origin' already exists
    if git remote | grep -q "origin"; then
        CURRENT_URL=$(git remote get-url origin)
        if [ "$CURRENT_URL" = "$REMOTE_URL" ]; then
            echo -e "${YELLOW}Notice:${NC} Remote 'origin' already set to ${REMOTE_URL}."
        else
            echo -e "${YELLOW}Notice:${NC} Remote 'origin' exists with URL ${CURRENT_URL}. Updating to ${REMOTE_URL}."
            git remote set-url origin "$REMOTE_URL"
            echo -e "${GREEN}Remote 'origin' updated.${NC}"
        fi
    else
        log "Adding remote 'origin'..."
        git remote add origin "$REMOTE_URL"
        echo -e "${GREEN}Remote 'origin' added.${NC}"
    fi

    # Determine default branch
    DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@')

    # Push to GitHub
    log "Pushing local repository to GitHub..."
    if git branch --show-current | grep -q "main\|master"; then
        CURRENT_BRANCH=$(git branch --show-current)
    else
        # If no branch exists, set to main
        git checkout -b main
        CURRENT_BRANCH="main"
    fi

    git push -u origin "$CURRENT_BRANCH"
    echo -e "${GREEN}Repository pushed to GitHub successfully on branch '${CURRENT_BRANCH}'.${NC}"
}

# -------------------- #
#      Main Execution    #
# -------------------- #

echo -e "${GREEN}Starting GitHub Repository Initialization...${NC}"

# Prepare the target directory
prepare_directory

# Preview actions
preview_actions

# Confirm before proceeding
confirm

# Create GitHub repository
create_github_repo

# Initialize Git repository
initialize_git_repo

# Create .gitignore file
create_gitignore

# Make initial commit
make_initial_commit

# Add remote origin and push
push_repository

echo -e "${GREEN}All operations completed successfully.${NC}"
