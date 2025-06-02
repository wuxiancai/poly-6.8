#!/bin/bash
set -e

# === 参数配置 ===
USER_NAME="admin"
USER_PASS="noneboy"
RESOLUTION="1920x1080"

echo "[1/12] 设置用户密码..."
echo "$USER_NAME:$USER_PASS" | sudo chpasswd

echo "[2/12] 系统更新..."
sudo apt update -y && sudo apt upgrade -y

echo "[3/12] 安装 MATE 桌面与 LightDM..."
sudo DEBIAN_FRONTEND=noninteractive apt install -y \
    mate-desktop-environment mate-desktop-environment-extras \
    mate-notification-daemon mate-tweak lightdm dbus-x11 xfonts-base

echo "[4/12] 配置 LightDM 自动登录..."
echo "/usr/sbin/lightdm" | sudo tee /etc/X11/default-display-manager
sudo tee /etc/lightdm/lightdm.conf > /dev/null <<EOF
[Seat:*]
autologin-user=$USER_NAME
autologin-user-timeout=0
user-session=mate
EOF

echo "[5/12] 安装 X2Go Server..."
sudo add-apt-repository ppa:x2go/stable -y
sudo apt update -y
sudo apt install -y x2goserver x2goserver-xsession x2gomatebindings

echo "[6/12] 安装网页VNC组件..."
sudo apt install -y x11vnc novnc websockify
sudo mkdir -p /etc/x11vnc
x11vnc -storepasswd "$USER_PASS" /etc/x11vnc/vncpasswd

sudo tee /etc/systemd/system/x11vnc.service > /dev/null <<EOF
[Unit]
Description=Start x11vnc at startup
After=multi-user.target

[Service]
Type=simple
ExecStart=/usr/bin/x11vnc -auth guess -forever -loop -noxdamage -repeat \
 -rfbauth /etc/x11vnc/vncpasswd -rfbport 5900 -display :0 -shared

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable x11vnc.service
sudo systemctl start x11vnc.service

echo "[7/12] 配置 noVNC 网页访问..."
sudo ln -s /usr/share/novnc /opt/novnc || true
sudo tee /etc/systemd/system/novnc.service > /dev/null <<EOF
[Unit]
Description=noVNC server
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/websockify --web=/usr/share/novnc/ 6080 localhost:5900

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable novnc.service
sudo systemctl start novnc.service

echo "[8/12] 配置 xprofile，设置分辨率与性能优化..."
sudo tee /home/$USER_NAME/.xprofile > /dev/null <<EOF
#!/bin/bash
xset s off
xset -dpms
dconf write /org/mate/marco/general/reduced-resources true
dconf write /org/mate/interface/enable-animations false
EOF
sudo chown $USER_NAME:$USER_NAME /home/$USER_NAME/.xprofile
sudo chmod +x /home/$USER_NAME/.xprofile

echo "[9/12] 安装智能QoS工具..."
sudo apt install -y wondershaper

sudo tee /usr/local/bin/smart_qos > /dev/null <<'EOF'
#!/bin/bash
INTERFACE="eth0"
CURRENT_BW=$(ifstat -i $INTERFACE 1 1 | tail -1 | awk '{print $1 + $2}')
if [ $(echo "$CURRENT_BW > 150000" | bc -l) -eq 1 ]; then
    /sbin/wondershaper $INTERFACE 5000 5000
    echo "[QoS] 高峰模式：保障5Mbps远程带宽"
else
    /sbin/wondershaper clear $INTERFACE
    echo "[QoS] 正常模式：无带宽限制"
fi
EOF
sudo chmod +x /usr/local/bin/smart_qos

sudo tee /etc/systemd/system/smart-qos.service > /dev/null <<EOF
[Unit]
Description=Dynamic QoS for Peak Hours
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/smart_qos
Restart=on-failure
RestartSec=60

[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/systemd/system/smart-qos.timer > /dev/null <<EOF
[Unit]
Description=Run QoS check every minute

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable smart-qos.timer
sudo systemctl start smart-qos.timer

echo "[10/12] 配置 BBR 与内核优化..."
sudo tee -a /etc/sysctl.conf > /dev/null <<EOF

# BBR & 网络优化
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.core.rmem_max=33554432
net.core.wmem_max=33554432
net.ipv4.tcp_rmem=4096 87380 33554432
net.ipv4.tcp_wmem=4096 65536 33554432
EOF

sudo sysctl -p

echo "[11/12] 设置默认启动图形界面..."
sudo systemctl set-default graphical.target
sudo systemctl restart lightdm

echo "[12/12] 安装监控工具..."
sudo apt install -y nload ifstat tcptrack

echo "✅ 部署完成！"

echo ""
echo "========================= 访问方式 ========================="
echo "X2Go 客户端：服务器IP，用户 admin，Session 类型：MATE"
echo "Web VNC 浏览器访问：http://你的IP:6080/"
echo "==========================================================="