#!/bin/bash

yarn version $1

cp package.json package.json.backup
jq 'del(.devDependencies, .optionalDependencies)' package.json.backup > package.json

npm publish

mv package.json.backup package.json