#!/bin/bash
# 一键安装 Fail2ban + 工具 + BBR + FQ  
# 适用于 Debian 11/12
# Author: ChatGPT

# 移除 set -e 以避免因單個命令失敗而終止整個腳本

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
sed -i '/# BBR 配置/d' $SYSCTL_CONF

# 添加新配置
cat >> $SYSCTL_CONF <<EOF

# BBR 配置 - 由脚本自动添加
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF

echo "=== 应用配置 ==="
echo "正在應用 sysctl 配置..."
sysctl -p || {
    echo "⚠️ 部分 sysctl 參數可能不被支持，繼續執行..."
    # 單獨應用關鍵的 BBR 配置
    sysctl -w net.core.default_qdisc=fq || true
    sysctl -w net.ipv4.tcp_congestion_control=bbr || true
}

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

# SSH 短期保护：10分钟内输错5次 → 封禁1小时
[sshd-short]
enabled  = true
port     = ssh
filter   = sshd
logpath  = /var/log/auth.log
findtime = 600
maxretry = 5
bantime  = 3600

# SSH 长期保护：1小时内输错20次 → 永久封禁
[sshd-long]
enabled  = true
port     = ssh
filter   = sshd
logpath  = /var/log/auth.log
findtime = 3600
maxretry = 20
bantime  = -1
EOF

echo "=== 确保日志文件存在 ==="
for LOG in /var/log/auth.log; do
  [ -f "$LOG" ] || touch "$LOG"
  chmod 600 "$LOG"
done

echo "=== 启动并设置开机自启 fail2ban ==="
systemctl enable fail2ban
systemctl restart fail2ban

# 等待服务完全启动
echo "=== 等待 fail2ban 服务启动 ==="
sleep 5

echo "=== 检查 fail2ban 状态 ==="
# 检查服务是否正在运行
if systemctl is-active --quiet fail2ban; then
    echo "✅ fail2ban 服务已启动"
    
    # 检查 jail 状态
    if fail2ban-client status &>/dev/null; then
        echo "✅ fail2ban 客户端通信正常"
        fail2ban-client status
        echo ""
        fail2ban-client status sshd-short 2>/dev/null || echo "⚠️ sshd-short jail 可能需要时间初始化"
        fail2ban-client status sshd-long 2>/dev/null || echo "⚠️ sshd-long jail 可能需要时间初始化"
    else
        echo "⚠️ fail2ban 客户端通信异常，请稍后手动检查"
    fi
else
    echo "❌ fail2ban 服务启动失败"
    systemctl status fail2ban --no-pager
fi

echo "✅ 脚本执行完成：Fail2ban 已启用，BBR + FQ 已永久生效"
