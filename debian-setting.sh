#!/bin/bash
# 一键安装并配置 fail2ban + 常用工具 + 永久开启 BBR + FQ
# 适用 Debian 11

set -e

echo "=== 更新系统包 ==="
apt update -y
apt install -y fail2ban curl wget sudo python3 unzip jq iperf3

echo "=== 检查内核版本 ==="
KERNEL=$(uname -r | cut -d. -f1)
if [ "$KERNEL" -lt 4 ]; then
    echo "内核版本过低 (<4.x)，不支持 BBR，请升级内核！"
    exit 1
fi

echo "=== 加载 tcp_bbr 模块（如果未加载） ==="
modprobe tcp_bbr || true

echo "=== 写入 sysctl 配置 ==="
SYSCTL_CONF="/etc/sysctl.conf"

# 清理旧配置
sed -i '/net\.core\.default_qdisc/d' $SYSCTL_CONF
sed -i '/net\.ipv4\.tcp_congestion_control/d' $SYSCTL_CONF

# 添加新配置
cat >> $SYSCTL_CONF <<EOF

# 启用 FQ 调度器 + BBR 拥塞控制
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF

echo "=== 应用配置 ==="
sysctl -p

echo "=== 验证 BBR 配置 ==="
sysctl net.ipv4.tcp_congestion_control
sysctl net.core.default_qdisc
lsmod | grep bbr || echo "⚠️ 警告: tcp_bbr 模块未加载"

echo "=== 停止并清理旧 fail2ban 配置 ==="
systemctl stop fail2ban || true
mv /etc/fail2ban/jail.local /etc/fail2ban/jail.local.bak.$(date +%s) 2>/dev/null || true

echo "=== 写入新配置 /etc/fail2ban/jail.local ==="
cat > /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
banaction = iptables-multiport
ignoreip = 127.0.0.1/8 ::1

# 短期保护：10分钟内输错5次 → 封禁1小时
[sshd-short]
enabled  = true
port     = ssh
filter   = sshd
logpath  = /var/log/auth.log
findtime = 600
maxretry = 5
bantime  = 3600

# 长期保护：1小时内输错20次 → 永久封禁
[sshd-hard]
enabled  = true
port     = ssh
filter   = sshd
logpath  = /var/log/auth.log
findtime = 3600
maxretry = 20
bantime  = -1
EOF

echo "=== 启动并设置开机自启 fail2ban ==="
systemctl enable fail2ban
systemctl restart fail2ban

echo "=== 完成！检查 fail2ban 状态 ==="
fail2ban-client status sshd-short
fail2ban-client status sshd-hard

echo "✅ 脚本执行完成：Fail2ban 已启用，BBR + FQ 已永久生效"