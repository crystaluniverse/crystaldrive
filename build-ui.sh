#!/bin/bash

sudo apt install -y git npm
pushd .
cd frontend
sed -i 's/'"'"'\[{\[ .StaticURL \]}\]/'"'"'\/static/g' vue.config.js
npm install
npm run build
popd
rm -rf public
mkdir -p public
cp -r frontend/dist public/static
