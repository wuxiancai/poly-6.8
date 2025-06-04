#!/bin/bash

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
sudo usermod -a -G lightdm admin
sudo usermod -a -G nopasswdlogin admin

echo "开始安装 LXDE, TigerVNC, noVNC ..."
# 1. 更新系统并安装必要软件包
apt update && apt upgrade -y
apt install -y lxde-core lightdm tigervnc-standalone-server tigervnc-common novnc websockify net-tools

# 2. 配置 LightDM 自动登录
echo "配置 LightDM 自动登录用户 ${USERNAME}..."
LIGHTDM_CONF="/etc/lightdm/lightdm.conf"
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

systemctl enable novnc.service
systemctl start novnc.service

# 尝试重启 lightdm 以应用自动登录 (如果系统当前在运行级别5，这可能会中断现有会话)
# systemctl restart lightdm

echo " "
echo "安装和配置完成!"
echo "TigerVNC 服务器应该在 display :${DISPLAY_NUM} (端口 ${VNC_PORT}) 上运行。"
echo "noVNC 应该在 http://<您的服务器IP>:${NOVNC_PORT}/vnc.html 上可用。"
echo "VNC 密码是: ${PASSWORD}"
echo "用户 ${USERNAME} 将在下次启动时自动登录到 LXDE 桌面。"
echo "如果遇到问题，请检查日志：journalctl -u vncserver@${DISPLAY_NUM} 和 journalctl -u novnc"
echo "以及 LightDM 日志 /var/log/lightdm/"
echo "您可能需要重启服务器以使所有更改完全生效，特别是 LightDM 自动登录。"
echo "sudo reboot"

exit 0