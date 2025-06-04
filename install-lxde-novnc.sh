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

# 7. 安装和配置 XRDP
echo "安装和配置 XRDP..."
apt install -y xrdp

# 配置 XRDP 连接到现有的 VNC 服务器
echo "配置 XRDP 连接到 VNC 服务器..."
cat <<EOF > /etc/xrdp/xrdp.ini
[Globals]
ini_version=1
fork=true
port=3389
tcp_nodelay=true
tcp_keepalive=true
security_layer=rdp
crypt_level=high
certificate=
key_file=
ssl_protocols=TLSv1.2, TLSv1.3
max_bpp=32
xserverbpp=24
channel_code=1
use_vsock=false

[Xvnc]
name=Xvnc
lib=libvnc.so
username=admin
password=ask
ip=127.0.0.1
port=5901
chansrvport=DISPLAY(10)
code=20
EOF

# 配置 XRDP 启动脚本
cat <<EOF > /etc/xrdp/startwm.sh
#!/bin/sh
# xrdp X session start script (c) 2015, 2017, 2021 mirabilos
# published under The MirOS Licence

# Rely on /etc/pam.d/xrdp-sesman using pam_env to load both
# /etc/environment and /etc/default/locale to initialise the
# locale and the user environment properly.

unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR
unset XDG_SESSION_ID

# 连接到现有的 VNC 服务器而不是启动新的桌面
if [ -r /etc/default/locale ]; then
  . /etc/default/locale
  export LANG LANGUAGE LC_ALL LC_PAPER LC_ADDRESS LC_MONETARY LC_NUMERIC LC_TELEPHONE LC_IDENTIFICATION LC_MEASUREMENT LC_TIME LC_NAME
fi

# 使用 Xvnc 连接到现有的 VNC 服务器
exec /usr/bin/xvnc4viewer -shared -viewonly=0 localhost:1
EOF

chmod +x /etc/xrdp/startwm.sh

# 创建 XRDP 用户配置
echo "配置 XRDP 用户认证..."
# 允许 admin 用户通过 XRDP 登录
echo "admin:noneboy" | chpasswd

# 配置 XRDP 服务
echo "启用 XRDP 服务..."
systemctl enable xrdp
systemctl enable xrdp-sesman

# 配置防火墙（如果需要）
echo "配置防火墙规则..."
if command -v ufw >/dev/null 2>&1; then
    ufw allow 3389/tcp
fi

# 启动 XRDP 服务
echo "启动 XRDP 服务..."
systemctl start xrdp
systemctl start xrdp-sesman

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


# 8. 安装和配置 X2GO
echo "安装和配置 X2GO..."
apt install -y x2goserver x2goserver-xsession

# 配置 X2GO 使用现有的 VNC 会话
echo "配置 X2GO 连接到现有 VNC 会话..."

# 创建 X2GO 会话配置
cat <<EOF > /etc/x2go/x2goserver.conf
# X2GO Server Configuration
# 使用现有的 VNC 会话而不是创建新的
use-nx=0
use-vnc=1
vnc-display=:1
vnc-password-file=/home/admin/.vnc/passwd
allow-tcp-connections=1
EOF

# 配置 X2GO 用户会话
mkdir -p /home/admin/.x2go
cat <<EOF > /home/admin/.x2go/sessions
# X2GO Session Configuration for admin user
# 连接到现有的 VNC 桌面会话
[LXDE-VNC]
name=LXDE Desktop (VNC)
command=x11vnc -display :1 -shared -forever -nopw -connect localhost:5901
type=application
EOF

chown -R admin:admin /home/admin/.x2go

# 创建 X2GO 启动脚本，连接到现有 VNC
cat <<EOF > /usr/local/bin/x2go-vnc-bridge
#!/bin/bash
# X2GO to VNC Bridge Script
# 这个脚本将 X2GO 会话桥接到现有的 VNC 服务器

export DISPLAY=:1
export XAUTHORITY=/home/admin/.Xauthority

# 检查 VNC 服务器是否运行
if ! pgrep -f "Xtigervnc :1" > /dev/null; then
    echo "VNC Server not running, starting..."
    su - admin -c "vncserver :1 -geometry 1920x1080 -depth 24"
    sleep 2
fi

# 启动 x11vnc 来桥接到现有的 VNC 会话
exec x11vnc -display :1 -shared -forever -nopw -rfbport 5902 -bg
EOF

chmod +x /usr/local/bin/x2go-vnc-bridge

# 配置 X2GO 使用我们的桥接脚本
cat <<EOF > /etc/x2go/applications
[LXDE]
name=LXDE Desktop
command=/usr/local/bin/x2go-vnc-bridge
icon=lxde
type=application
categories=Desktop
EOF

# 确保 admin 用户可以使用 X2GO
echo "配置 X2GO 用户权限..."
usermod -a -G x2gouser admin 2>/dev/null || true

# 创建 X2GO systemd 服务
echo "创建 X2GO systemd 服务..."
cat <<EOF > /etc/systemd/system/x2goserver.service
[Unit]
Description=X2GO Server
After=network.target vncserver@1.service
Requires=vncserver@1.service

[Service]
Type=forking
ExecStart=/usr/sbin/x2gocleansessions
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=mixed
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 启用并启动 X2GO 服务
echo "启用并启动 X2GO 服务..."
systemctl daemon-reload
systemctl enable x2goserver.service
systemctl start x2goserver.service

# 配置防火墙（如果需要）
echo "配置 X2GO 防火墙规则..."
if command -v ufw >/dev/null 2>&1; then
    ufw allow 22/tcp  # X2GO 使用 SSH 端口
fi

echo ""
echo "X2GO 配置完成!"
echo "现在可以通过以下方式访问桌面："
echo "1. Windows 远程桌面连接: ${PUBLIC_IP:-<IP>}:3389"
echo "   用户名: admin, 密码: noneboy"
echo "2. X2GO 客户端连接: ${PUBLIC_IP:-<IP>}:22"
echo "   用户名: admin, 密码: noneboy"
echo "   会话类型: LXDE Desktop"
echo "3. noVNC Web界面: http://${PUBLIC_IP:-<IP>}:${NOVNC_PORT}/vnc.html"
echo "   密码: ${PASSWORD}"
echo "4. VNC 客户端: ${PUBLIC_IP:-<IP>}:${VNC_PORT}"
echo "   密码: ${PASSWORD}"
echo ""
echo "注意: 所有连接方式都共享同一个 LXDE 桌面会话。"
echo "X2GO 客户端下载: https://wiki.x2go.org/doku.php/download:start"