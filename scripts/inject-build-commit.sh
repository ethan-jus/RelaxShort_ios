#!/bin/sh
# TASK-0001-A 收尾：将当前 git commit SHA 注入构建产物 Info.plist，
# 使启动日志中的 BuildCommit 始终与 git rev-parse --short HEAD 一致。
# 方案：直接写入 TARGET_BUILD_DIR 中的 Info.plist（不影响源码 Info.plist）。

set -eu

COMMIT=$(git -C "${SRCROOT}" rev-parse --short HEAD 2>/dev/null || echo "unknown")

/usr/libexec/PlistBuddy -c "Set :BuildCommit ${COMMIT}" \
    "${TARGET_BUILD_DIR}/${INFOPLIST_PATH}" 2>/dev/null || {
    /usr/libexec/PlistBuddy -c "Add :BuildCommit string ${COMMIT}" \
        "${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
}

echo "BuildCommit injected: ${COMMIT}"
