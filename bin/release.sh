#!/usr/bin/env bash

set -e

if [ ! -z $DRY_RUN ]; then
  echo "Doing a dry run release..."
elif [ ! -z $BETA ]; then
  echo "Doing a beta release to npm..."
else
  echo "Doing a real release! Use DRY_RUN=1 for a dry run instead."
fi

#make sure deps are up to date
#rm -fr node_modules
npm install

# get current version
VERSION=$(node --eval "console.log(require('./package.json').version);")

# Create a temporary build directory
SOURCE_DIR=$(git name-rev --name-only HEAD)
BUILD_DIR=build_"${RANDOM}"
git checkout -b $BUILD_DIR

# Update dependency versions inside each package.json (replace the "*")
node bin/update-package-json-for-publish.js

# Publish all modules with Lerna
for pkg in $(ls packages/node_modules); do
  if [ ! -d "packages/node_modules/$pkg" ]; then
    continue
  elif [ "true" = $(node --eval "console.log(require('./packages/node_modules/$pkg/package.json').private);") ]; then
    continue
  fi
  cd packages/node_modules/$pkg
  echo "Publishing $pkg..."
  if [ ! -z $DRY_RUN ]; then
    echo "Dry run, not publishing"
  elif [ ! -z $BETA ]; then
    npm publish --tag beta
  else
    npm publish
  fi
  cd -
done

# Build browser packages
for pkg in $(ls packages/node_modules); do
  if [ "false" = $(node --eval "console.log(!!require('./package.json').browserPackages['$pkg']);") ]; then
      continue
  fi
  module_name=$(node --eval "console.log(require('./package.json').browserPackages['$pkg']);")
  browserify packages/node_modules/$pkg -o packages/node_modules/$pkg/dist/$pkg.js -s $module_name
  uglifyjs packages/node_modules/$pkg/dist/$pkg.js -o packages/node_modules/$pkg/dist/$pkg.min.js
done

# Create git tag, which is also the Bower/Github release
git add -f ./packages/node_modules/*/dist
git commit -m "build $VERSION"

# Only "publish" to GitHub/Bower if this is a non-beta non-dry run
if [ -z $DRY_RUN ]; then
 if [ -z $BETA ]; then
    # Tag and push
    git tag $VERSION
    git push --tags git@github.com:pouchdb/pouchdb-server.git $VERSION

    # Cleanup
    git checkout $SOURCE_DIR
    git branch -D $BUILD_DIR
  fi
fi
