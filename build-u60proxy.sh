#!/bin/sh
set -eu
mkdir -p bin
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -trimpath -ldflags='-s -w' -o bin/u60proxy ./cmd/u60proxy
