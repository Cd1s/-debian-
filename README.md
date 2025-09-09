# Debian 11 一键初始化脚本

这是一个用于 **Debian 11** 的一键初始化脚本，功能包括：

- 安装 Fail2ban 并配置 SSH 短期/长期防爆破规则
- 安装常用工具：curl、wget、sudo、python3、unzip、jq、iperf3
- 开启 BBR + FQ 拥塞控制优化网络性能

---

## 1. 使用方法（推荐一键执行）

直接在终端运行以下命令即可：

```bash
bash <(wget -qO- https://raw.githubusercontent.com/Cd1s/-debian-/refs/heads/main/debian-setting.sh)
