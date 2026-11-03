module github.com/zachgree/rodinia-client/core

go 1.27

require github.com/xtls/xray-core v0.0.0

// Pinned by scripts/build-core.sh, which clones the tagged release here.
replace github.com/xtls/xray-core => ../.build/Xray-core
