#!/bin/bash -xe

GIT_ROOT=$(git rev-parse --show-toplevel)

# Install node packages if this particular repo has a package.json
[ -f "$GIT_ROOT/package.json" ] && npm install

echo "Hatch (Python): $(hatch --version)"
