#!/bin/sh

# Debug 真机每次构建前读取 Mac 当前局域网 IPv4，只修改构建产物，不改动仓库中的 Info.plist。
set -u

if [ "${CONFIGURATION:-}" != "Debug" ]; then
    exit 0
fi

plist="${TARGET_BUILD_DIR:-}/${INFOPLIST_PATH:-}"
if [ ! -f "$plist" ]; then
    echo "warning: 未找到构建产物 Info.plist，跳过局域网 API 地址注入: $plist"
    exit 0
fi

default_interface=$(/sbin/route -n get default 2>/dev/null | /usr/bin/awk '/interface:/{print $2; exit}')
interfaces="$default_interface en0 en1"
ip=""

for interface in $interfaces; do
    [ -n "$interface" ] || continue
    candidate=$(/usr/sbin/ipconfig getifaddr "$interface" 2>/dev/null || true)
    case "$candidate" in
        10.*|192.168.*|172.16.*|172.17.*|172.18.*|172.19.*|172.2[0-9].*|172.3[0-1].*)
            ip="$candidate"
            break
            ;;
    esac
done

if [ -z "$ip" ]; then
    echo "warning: 未找到 Mac 局域网 IPv4，Debug API 地址保留为构建默认值"
    exit 0
fi

api_url="http://${ip}:8080"
/usr/libexec/PlistBuddy -c "Delete :API_BASE_URL" "$plist" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c "Add :API_BASE_URL string ${api_url}" "$plist"
echo "Debug API 地址已自动注入: ${api_url}"
