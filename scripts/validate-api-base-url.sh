#!/bin/sh

# 验证 Xcode build setting 注入的 API_BASE_URL。
# Debug 真机禁止 loopback；Release 必须使用外部 HTTPS 地址。
set -eu

api_url="${API_BASE_URL:-}"

if [ "${CONFIGURATION:-}" = "Debug" ]; then
    case "$api_url" in
        http://*|https://*)
            ;;
        *)
            echo "error: Debug 构建缺少有效的 API_BASE_URL"
            exit 1
            ;;
    esac

    case "${SDK_NAME:-}" in
        iphoneos*)
            case "$api_url" in
                *://127.0.0.1:*|*://localhost:*)
                    echo "error: Debug 真机不能使用 loopback API 地址: ${api_url}"
                    exit 1
                    ;;
            esac
            ;;
    esac

    echo "Debug API 地址: ${api_url}"
    exit 0
fi

case "$api_url" in
    https://localhost*|https://127.0.0.1*)
        echo "error: Release API 地址不能指向本机: ${api_url}"
        exit 1
        ;;
    https://*)
        echo "Release API 地址已配置"
        ;;
    *)
        echo "error: Release 构建必须通过 RELAXSHORT_API_BASE_URL 注入正式 HTTPS API 地址"
        exit 1
        ;;
esac
