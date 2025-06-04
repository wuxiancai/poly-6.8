#!/bin/bash

# 获取公网IP地址
echo "正在获取公网IP地址..."
PUBLIC_IP=""

# 尝试多个服务获取公网IP，增加成功率
for service in "curl -s ifconfig.me" "curl -s ipinfo.io/ip" "curl -s icanhazip.com" "curl -s ident.me" "wget -qO- ifconfig.me"; do
    if command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1; then
        PUBLIC_IP=$(eval $service 2>/dev/null | tr -d '\n\r')
        if [[ $PUBLIC_IP =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo "检测到公网IP: $PUBLIC_IP"
            break
        fi
    fi
done

# 如果无法获取公网IP，使用本地IP作为备选
if [ -z "$PUBLIC_IP" ]; then
    echo "无法获取公网IP，尝试获取本地IP..."
    LOCAL_IP=$(hostname -I | awk '{print $1}' 2>/dev/null || ip route get 1 | awk '{print $NF;exit}' 2>/dev/null)
    if [ -n "$LOCAL_IP" ]; then
        PUBLIC_IP="$LOCAL_IP"
        echo "使用本地IP: $PUBLIC_IP"
    else
        PUBLIC_IP="<您的服务器IP>"
        echo "警告: 无法自动获取IP地址，请手动替换 $PUBLIC_IP"
    fi
fi

# 设置非交互式环境变量
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

# 创建 admin 用户（如不存在）
id admin &>/dev/null || sudo adduser admin
echo 'admin:noneboy' | sudo chpasswd
usermod -aG sudo admin

# 检查是否以root用户运行
if [ "$(id -u)" -ne 0 ]; then
  echo "请以root用户或使用sudo运行此脚本。" >&2
  exit 1
fi

USERNAME="admin"
PASSWORD="noneboy"
DISPLAY_NUM="1"
RESOLUTION="1920x1080"
NOVNC_PORT="6080"
VNC_PORT=$((5900 + ${DISPLAY_NUM}))

# 预配置 LightDM 以避免交互式提示
echo "预配置软件包以避免交互式提示..."
echo 'lightdm lightdm/default-x-display-manager select lightdm' | debconf-set-selections
echo 'shared/default-x-display-manager select lightdm' | debconf-set-selections

# 创建用户组（如果不存在）
getent group lightdm >/dev/null || groupadd lightdm
getent group nopasswdlogin >/dev/null || groupadd nopasswdlogin

# 添加用户到组（静默处理错误）
usermod -a -G lightdm admin 2>/dev/null || true
usermod -a -G nopasswdlogin admin 2>/dev/null || true


echo "开始安装 LXDE, TigerVNC, noVNC ..."
# 1. 更新系统并安装必要软件包（非交互式）
echo "更新软件包列表..."
apt update -qq

echo "升级系统软件包..."
apt upgrade -y -qq

echo "安装必要软件包..."
# 分步安装以便更好的错误处理
apt install -y -qq --no-install-recommends curl wget ca-certificates
apt install -y -qq --no-install-recommends lxde-core
apt install -y -qq --no-install-recommends lightdm
apt install -y -qq --no-install-recommends tigervnc-standalone-server tigervnc-common
apt install -y -qq --no-install-recommends novnc websockify
apt install -y -qq --no-install-recommends net-tools nload ifstat glances
pip3 install glances[web]

# 2. 配置 LightDM 自动登录
echo "配置 LightDM 自动登录用户 ${USERNAME}..."
LIGHTDM_CONF="/etc/lightdm/lightdm.conf"

# 停止 LightDM 服务以避免配置冲突
systemctl stop lightdm 2>/dev/null || true

if [ -f "${LIGHTDM_CONF}" ]; then
    sed -i "s/^#\?autologin-user=.*/autologin-user=${USERNAME}/" "${LIGHTDM_CONF}"
    sed -i "s/^#\?autologin-session=.*/autologin-session=lxde/" "${LIGHTDM_CONF}"
    # 确保 [Seat:*] 或 [SeatDefaults] 部分存在这些行
    if ! grep -q "^\[Seat:\*\]" "${LIGHTDM_CONF}" && ! grep -q "^\[SeatDefaults\]" "${LIGHTDM_CONF}"; then
        echo "\n[Seat:*]" >> "${LIGHTDM_CONF}"
        echo "autologin-user=${USERNAME}" >> "${LIGHTDM_CONF}"
        echo "autologin-session=lxde" >> "${LIGHTDM_CONF}"
    elif ! grep -q "^autologin-user=" "${LIGHTDM_CONF}"; then
        sed -i "/\[Seat:\*\]/a autologin-user=${USERNAME}" "${LIGHTDM_CONF}"
        sed -i "/\[SeatDefaults\]/a autologin-user=${USERNAME}" "${LIGHTDM_CONF}"
    fi
    if ! grep -q "^autologin-session=" "${LIGHTDM_CONF}"; then
        sed -i "/\[Seat:\*\]/a autologin-session=lxde" "${LIGHTDM_CONF}"
        sed -i "/\[SeatDefaults\]/a autologin-session=lxde" "${LIGHTDM_CONF}"
    fi
else
    echo "创建 ${LIGHTDM_CONF} ..."
    mkdir -p /etc/lightdm
    cat <<EOF > "${LIGHTDM_CONF}"
[Seat:*]
autologin-user=admin
autologin-session=LXDE
autologin-user-timeout=0
autologin-guest=false
EOF
fi

# 3. 配置 TigerVNC Server for admin user
echo "为用户 ${USERNAME} 配置 TigerVNC..."

# 切换到 admin 用户执行 vncpasswd，然后切回
su - ${USERNAME} -c "mkdir -p /home/${USERNAME}/.vnc && echo '${PASSWORD}' | vncpasswd -f > /home/${USERNAME}/.vnc/passwd && chmod 600 /home/${USERNAME}/.vnc/passwd"

# 创建 xstartup 文件
cat <<EOF > "/home/${USERNAME}/.vnc/xstartup"
#!/bin/bash
export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=LXDE
export DESKTOP_SESSION=LXDE
[ -x /etc/vnc/xstartup ] && exec /etc/vnc/xstartup
[ -r \$HOME/.Xresources ] && xrdb \$HOME/.Xresources
xsetroot -solid grey
/usr/bin/lxsession -s LXDE -e LXDE
EOF
chmod +x "/home/${USERNAME}/.vnc/xstartup"
chown -R ${USERNAME}:${USERNAME} "/home/${USERNAME}/.vnc"

# 4. 创建 TigerVNC systemd 服务文件
echo "创建 TigerVNC systemd 服务..."
cat <<EOF > /etc/systemd/system/vncserver@.service
[Unit]
Description=Remote desktop service (VNC)
After=syslog.target network.target

[Service]
Type=simple
User=admin
Group=admin
WorkingDirectory=/home/admin
Environment=HOME=/home/admin
Environment=USER=admin
Environment=DISPLAY=:%i

ExecStartPre=-/usr/bin/vncserver -kill :%i > /dev/null 2>&1
ExecStart=/usr/bin/vncserver -depth 24 -geometry 1920x1080 :%i -localhost no -fg
ExecStop=/usr/bin/vncserver -kill :%i
Restart=on-failure
RestartSec=5
TimeoutStartSec=30

[Install]
WantedBy=multi-user.target
EOF

# 5. 创建 noVNC systemd 服务文件
echo "创建 noVNC systemd 服务..."
cat <<EOF > /etc/systemd/system/novnc.service
[Unit]
Description=noVNC Service
After=network.target vncserver@${DISPLAY_NUM}.service
Requires=vncserver@${DISPLAY_NUM}.service

[Service]
Type=simple
User=${USERNAME}
ExecStart=/usr/bin/websockify --web=/usr/share/novnc/ ${NOVNC_PORT} localhost:${VNC_PORT}
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# 6. 启用并启动服务
echo "启用并启动服务..."
systemctl daemon-reload
systemctl enable vncserver@${DISPLAY_NUM}.service
systemctl start vncserver@${DISPLAY_NUM}.service

# 等待 VNC 服务启动
echo "等待 VNC 服务启动..."
sleep 5

echo "启用并启动 noVNC 服务..."
systemctl enable novnc.service
systemctl start novnc.service


# 检查服务状态
echo "检查服务状态..."
if systemctl is-active --quiet vncserver@${DISPLAY_NUM}.service; then
    echo "✓ VNC 服务运行正常"
else
    echo "✗ VNC 服务启动失败"
    systemctl status vncserver@${DISPLAY_NUM}.service --no-pager
fi

if systemctl is-active --quiet novnc.service; then
    echo "✓ noVNC 服务运行正常"
else
    echo "✗ noVNC 服务启动失败"
    systemctl status novnc.service --no-pager
fi

echo "安装完成,现在可以通过以下方式访问桌面："
echo "1. noVNC Web界面: http://${PUBLIC_IP:-<IP>}:${NOVNC_PORT}/vnc.html"
echo "   密码: ${PASSWORD}"
echo "2. VNC 客户端: ${PUBLIC_IP:-<IP>}:${VNC_PORT}"
echo "   密码: ${PASSWORD}"
echo ""
echo "注意: 所有连接方式都共享同一个 LXDE 桌面会话。"

sleep 10
# 配置带宽监控glances
cat <<EOF > /etc/systemd/system/glances-web.service
[Unit]
Description=Glances in Web Mode
After=network.target

[Service]
ExecStart=/usr/bin/glances -w
Restart=always
User=admin
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable glances-web.service
systemctl start glances-web.service

echo "🚀 正在配置 LXDE 永不休眠、不锁屏..."

LXDE_AUTOSTART="$HOME/.config/lxsession/LXDE/autostart"

# 创建目录
mkdir -p "$(dirname "$LXDE_AUTOSTART")"

# 准备追加的配置内容
read -r -d '' CONFIG_BLOCK <<EOF
@xset s off
@xset -dpms
@xset s noblank
@lxsession-default-apps screensaver none
EOF

# 检查是否已经存在配置
for line in "@xset s off" "@xset -dpms" "@xset s noblank" "@lxsession-default-apps screensaver none"; do
    if ! grep -Fxq "$line" "$LXDE_AUTOSTART" 2>/dev/null; then
        echo "$line" >> "$LXDE_AUTOSTART"
        echo "✅ 已添加: $line"
    else
        echo "ℹ️ 已存在: $line"
    fi
done

# 修改 logind.conf
echo "🛠️ 修改系统休眠策略..."
sudo sed -i 's/^#*HandleLidSwitch=.*/HandleLidSwitch=ignore/' /etc/systemd/logind.conf
sudo sed -i 's/^#*HandleLidSwitchDocked=.*/HandleLidSwitchDocked=ignore/' /etc/systemd/logind.conf
sudo sed -i 's/^#*IdleAction=.*/IdleAction=ignore/' /etc/systemd/logind.conf
sudo systemctl restart systemd-logind
echo "🔁 已重启 systemd-logind"

# 卸载可能干扰的屏保组件
echo "🗑️ 正在卸载 xscreensaver 和 light-locker..."
sudo apt remove -y xscreensaver light-locker

# 防止 xscreensaver 自启
(crontab -l 2>/dev/null | grep -v xscreensaver; echo "@reboot pkill xscreensaver") | crontab -
echo "🔒 已添加 pkill xscreensaver 到开机启动"

echo "✅ 配置完成，建议注销或重启 LXDE 以生效"

reboot