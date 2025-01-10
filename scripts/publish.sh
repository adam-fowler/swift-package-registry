#!/bin/bash

NAME_WITH_OWNER=$1

cleanup()
{
    if [ -n "$TEMP_DIR" ]; then
        rm -rf $TEMP_DIR
    fi
}

writePackageMetadata() 
{
    if [[ $OWNER_TYPE == "Organization" ]]; then
        AUTHOR_ID=$(echo $VERSION_METADATA | jq -r '.author.id')
        AUTHOR_METADATA=$(gh api "https://api.github.com/user/$AUTHOR_ID")

        AUTHOR_NAME=$(echo $AUTHOR_METADATA | jq '.name')
        AUTHOR_EMAIL=$(echo $AUTHOR_METADATA | jq '.email')
        AUTHOR_DESCRIPTION=$(echo $AUTHOR_METADATA | jq '.bio')
        AUTHOR_URL=$(echo $AUTHOR_METADATA | jq '.html_url')

        ORG_ID=$(echo $METADATA | jq -r '.owner.id')
        ORG_METADATA=$(gh api "https://api.github.com/user/$ORG_ID")
        ORG_NAME=$(echo $ORG_METADATA | jq '.name')
        ORG_DESCRIPTION=$(echo $ORG_METADATA | jq '.bio')
        ORG_URL=$(echo $ORG_METADATA | jq '.html_url')
        ORG_JSON=",
            \"organization\": {\"name\":$ORG_NAME, \"description\":$ORG_DESCRIPTION, \"url\":$ORG_URL}"
    else
        AUTHOR_ID=$(echo $METADATA | jq -r '.owner.id')
        AUTHOR_METADATA=$(gh api "https://api.github.com/user/$AUTHOR_ID")

        AUTHOR_NAME=$(echo $AUTHOR_METADATA | jq '.name')
        AUTHOR_EMAIL=$(echo $AUTHOR_METADATA | jq '.email')
        AUTHOR_DESCRIPTION=$(echo $AUTHOR_METADATA | jq '.bio')
        AUTHOR_URL=$(echo $AUTHOR_METADATA | jq '.html_url')
        ORG_JSON=""
    fi

cat > "package-metadata.json" <<EOF
{
    "author": {
        "name": $AUTHOR_NAME,
        "email": $AUTHOR_EMAIL,
        "description": $AUTHOR_DESCRIPTION,
        "url": $AUTHOR_URL$ORG_JSON
    },
    "description": $DESCRIPTION,
    "repositoryURLs": [
        $CLONE_URL,
        $SSH_URL
    ]
}
EOF
}

trap cleanup EXIT $?

TEMP_DIR=$(mktemp -d)
echo "Using temp folder $TEMP_DIR"

METADATA=$(gh api "https://api.github.com/repos/$NAME_WITH_OWNER")
VERSION_METADATA=$(gh api "https://api.github.com/repos/$NAME_WITH_OWNER/releases/latest")
OWNER_TYPE=$(echo $METADATA | jq -r '.owner.type')

DESCRIPTION=$(echo $METADATA | jq '.description')
CLONE_URL=$(echo $METADATA | jq '.clone_url')
SSH_URL=$(echo $METADATA | jq '.ssh_url')

LATEST_VERSION=$(echo $VERSION_METADATA | jq -r '.tag_name')
VERSION=${2:-$LATEST_VERSION}

echo "Cloning $NAME_WITH_OWNER ..."

git clone --depth 1 --branch $VERSION https://github.com/$NAME_WITH_OWNER $TEMP_DIR &> /dev/null

if [ $? -ne 0 ]; then
    echo "$VERSION does not exist"
    exit
fi 

cd $TEMP_DIR

writePackageMetadata

OWNER_NAME=$(echo $METADATA | jq -r '.owner.login')
PACKAGE_NAME=$(echo $METADATA | jq -r '.name')
PACKAGE_ID="$OWNER_NAME.$PACKAGE_NAME"

echo "Publishing $PACKAGE_ID v$VERSION ..."

swift package-registry publish $PACKAGE_ID $VERSION