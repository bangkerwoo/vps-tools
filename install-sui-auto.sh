#!/usr/bin/env bash

# ============================================================
# S-UI automatic installer
# Repository: bangkerwoo/vps-tools
#
# 功能：
# - 安装固定版本 S-UI
# - 自动生成面板端口和订阅端口
# - 自动生成面板路径和订阅路径
# - 自动生成管理员用户名和强密码
# - 保存登录凭据到仅 root 可读的文件
# - 检查服务及监听端口
# ============================================================

set -Eeuo pipefail
umask 077

readonly SUI_VERSION="v1.5.4"
readonly SUI_REPO="alireza0/s-ui"
readonly INSTALL_URL="https://raw.githubusercontent.com/${SUI_REPO}/${SUI_VERSION}/install.sh"
readonly CREDENTIAL_FILE="/root/s-ui-credentials.txt"

log() {
printf '[INFO] %s\n' "$*"
}

success() {
printf '[OK] %s\n' "$*"
}

die() {
printf '[ERROR] %s\n' "$*" >&2
exit 1
}

require_root() {
[[ "${EUID}" -eq 0 ]] || die "请使用 root 用户运行。"
}

install_dependencies() {
local missing=()

for cmd in curl openssl ss awk grep sha256sum; do
command -v "${cmd}" >/dev/null 2>&1 || missing+=("${cmd}")
done

if [[ "${#missing[@]}" -eq 0 ]]; then
return
fi

log "正在安装必要工具……"

if command -v apt-get >/dev/null 2>&1; then
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y curl openssl iproute2 coreutils gawk grep
elif command -v dnf >/dev/null 2>&1; then
dnf install -y curl openssl iproute coreutils gawk grep
elif command -v yum >/dev/null 2>&1; then
yum install -y curl openssl iproute coreutils gawk grep
else
die "暂不支持当前系统的软件包管理器。"
fi
}

random_alnum() {
local length="$1"

openssl rand -base64 64 |
tr -dc 'A-Za-z0-9' |
head -c "${length}"
}

random_lower() {
local length="$1"

openssl rand -base64 64 |
tr -dc 'a-z0-9' |
head -c "${length}"
}

port_in_use() {
local port="$1"

ss -H -lnt |
awk '{print $4}' |
grep -Eq "[:.]${port}$"
}

random_free_port() {
local port

while true; do
port="$(
od -An -N2 -tu2 /dev/urandom |
awk '{print 20000 + ($1 % 40001)}'
)"

if ! port_in_use "${port}"; then
printf '%s\n' "${port}"
return
fi
done
}

get_public_ip() {
local ip

ip="$(
curl \
--fail \
--silent \
--show-error \
--max-time 10 \
https://api.ipify.org 2>/dev/null || true
)"

if [[ -n "${ip}" ]]; then
printf '%s\n' "${ip}"
else
hostname -I | awk '{print $1}'
fi
}

require_root
install_dependencies

if [[ -e /usr/local/s-ui/sui ]]; then
die "检测到 S-UI 已安装。自动安装脚本只用于全新 VPS。"
fi

PANEL_PORT="$(random_free_port)"

while true; do
SUBSCRIPTION_PORT="$(random_free_port)"
[[ "${SUBSCRIPTION_PORT}" != "${PANEL_PORT}" ]] && break
done

PANEL_PATH="$(random_lower 14)"
SUBSCRIPTION_PATH="$(random_lower 16)"
ADMIN_USERNAME="u$(random_lower 11)"
ADMIN_PASSWORD="$(random_alnum 24)"

TEMP_INSTALLER="$(mktemp /tmp/s-ui-auto-install.XXXXXX.sh)"

cleanup() {
rm -f "${TEMP_INSTALLER}"
}

trap cleanup EXIT

log "下载 S-UI ${SUI_VERSION} 官方安装脚本……"

curl \
--fail \
--location \
--proto '=https' \
--tlsv1.2 \
--retry 3 \
--connect-timeout 10 \
--max-time 120 \
--silent \
--show-error \
"${INSTALL_URL}" \
--output "${TEMP_INSTALLER}"

[[ -s "${TEMP_INSTALLER}" ]] || die "官方安装脚本为空。"

log "官方安装脚本 SHA-256："
sha256sum "${TEMP_INSTALLER}"

log "使用官方默认值完成基础安装……"

# 官方安装程序询问是否修改默认设置时，自动选择 n。
printf 'n\n' |
SUI_LANG=zhcn bash "${TEMP_INSTALLER}" "${SUI_VERSION}"

[[ -x /usr/local/s-ui/sui ]] ||
die "没有找到 /usr/local/s-ui/sui，安装可能失败。"

log "设置随机管理员账号……"

/usr/local/s-ui/sui admin \
-username "${ADMIN_USERNAME}" \
-password "${ADMIN_PASSWORD}"

log "设置随机面板及订阅参数……"

/usr/local/s-ui/sui setting \
-port "${PANEL_PORT}" \
-path "${PANEL_PATH}" \
-subPort "${SUBSCRIPTION_PORT}" \
-subPath "${SUBSCRIPTION_PATH}"

systemctl restart s-ui
sleep 3

systemctl is-active --quiet s-ui ||
die "S-UI 服务没有正常启动。"

PUBLIC_IP="$(get_public_ip)"

cat > "${CREDENTIAL_FILE}" <<EOF
S-UI installation information
Generated: $(date '+%F %T %Z')
Version: ${SUI_VERSION}

Panel URL:
http://${PUBLIC_IP}:${PANEL_PORT}/${PANEL_PATH}/

Admin username:
${ADMIN_USERNAME}

Admin password:
${ADMIN_PASSWORD}

Subscription base URL:
http://${PUBLIC_IP}:${SUBSCRIPTION_PORT}/${SUBSCRIPTION_PATH}/

Panel port:
${PANEL_PORT}

Subscription port:
${SUBSCRIPTION_PORT}
EOF

chmod 600 "${CREDENTIAL_FILE}"

echo
echo "============================================================"
echo " S-UI 安装成功"
echo "============================================================"
echo
echo "面板地址："
echo "http://${PUBLIC_IP}:${PANEL_PORT}/${PANEL_PATH}/"
echo
echo "管理员用户名："
echo "${ADMIN_USERNAME}"
echo
echo "管理员密码："
echo "${ADMIN_PASSWORD}"
echo
echo "订阅基础地址："
echo "http://${PUBLIC_IP}:${SUBSCRIPTION_PORT}/${SUBSCRIPTION_PATH}/"
echo
echo "凭据保存位置："
echo "${CREDENTIAL_FILE}"
echo
echo "服务状态："
systemctl is-active s-ui
echo
echo "监听端口："
ss -lntp |
grep -E ":(${PANEL_PORT}|${SUBSCRIPTION_PORT})\\b" || true
echo
echo "请妥善保存凭据，不要截图公开密码。"
echo "============================================================"

success "全部流程已完成。"
