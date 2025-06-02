#!/bin/bash
set -e

USER_NAME="admin"
USER_PASS="noneboy"
RESOLUTION="1920x1080"

echo "[1/10] 设置用户密码与基础环境..."
echo "$USER_NAME:$USER_PASS" | sudo chpasswd
sudo apt update -y
sudo apt upgrade -y

echo "[2/10] 安装 MATE 桌面环境..."
sudo DEBIAN_FRONTEND=noninteractive apt install -y \
    mate-desktop-environment mate-desktop-environment-extras \
    mate-session-manager dbus-x11 xfonts-base

echo "[3/10] 安装 X2Go Server..."
sudo add-apt-repository ppa:x2go/stable -y
sudo apt update -y
sudo apt install -y x2goserver x2goserver-xsession x2gomatebindings

echo "[4/10] 修复 X2Go 会话启动..."
# 创建 .xsession，指明 MATE 桌面
sudo -u "$USER_NAME" bash -c "echo 'mate-session' > /home/$USER_NAME/.xsession"
sudo chown "$USER_NAME:$USER_NAME" /home/$USER_NAME/.xsession
sudo chmod +x /home/$USER_NAME/.xsession

echo "[5/10] 配置 X2Go 极致抗高峰参数..."
sudo tee /etc/x2go/x2goagent.options > /dev/null <<EOF
X2GO_NXAGENT_DEFAULT_OPTIONS="--link=adsl --cache=32M --pack=8m-jpeg-9"
AGENT_EXTRA_OPTIONS="-nolisten tcp -deferupdate 100"
COMPRESS_LEVEL=9
EOF

echo "[6/10] 启用 TCP BBR 与网络优化..."
sudo tee -a /etc/sysctl.conf <<EOF
net.core.default_qdisc=fq_pie
net.ipv4.tcp_congestion_control=bbr
net.core.rmem_max=33554432
net.core.wmem_max=33554432
net.ipv4.tcp_rmem=4096 131072 33554432
net.ipv4.tcp_wmem=4096 131072 33554432
net.ipv4.tcp_sack=1
net.ipv4.tcp_fack=1
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_slow_start_after_idle=0
EOF
sudo sysctl -p

echo "[7/10] 安装智能 QoS 控制器..."
sudo apt install -y wondershaper bc ifstat

sudo tee /usr/local/bin/smart_qos <<'EOF'
#!/bin/bash
INTERFACE="eth0"
CURRENT_BW=$(ifstat -i $INTERFACE 1 1 | tail -1 | awk '{print $1 + $2}')
if [ $(echo "$CURRENT_BW > 150000" | bc -l) -eq 1 ]; then
    /sbin/wondershaper $INTERFACE 5000 5000
    echo "[QoS] 高峰模式：5Mbps保障"
else
    /sbin/wondershaper clear $INTERFACE
    echo "[QoS] 正常模式：无限制"
fi
EOF

sudo chmod +x /usr/local/bin/smart_qos

sudo tee /etc/systemd/system/smart-qos.service <<EOF
[Unit]
Description=Smart QoS Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/smart_qos
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/systemd/system/smart-qos.timer <<EOF
[Unit]
Description=Smart QoS Timer

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable smart-qos.timer
sudo systemctl start smart-qos.timer

echo "[8/10] 分辨率与性能优化..."
sudo -u "$USER_NAME" tee /home/$USER_NAME/.xprofile > /dev/null <<EOF
#!/bin/bash
xset s off
xset -dpms
dconf write /org/mate/marco/general/reduced-resources true
dconf write /org/mate/interface/enable-animations false
EOF

sudo chown "$USER_NAME:$USER_NAME" /home/$USER_NAME/.xprofile
sudo chmod +x /home/$USER_NAME/.xprofile

echo "[9/10] 安装网络监控工具..."
sudo apt install -y nload ifstat tcptrack

echo "[10/10] 重启 X2Go 服务..."
sudo systemctl restart x2goserver

echo "[11/11] 安装并配置 Web VNC 支持 (x11vnc + noVNC)..."

# 安装 x11vnc（共享实际桌面）
sudo apt install -y x11vnc

# 设置 VNC 密码（默认使用用户密码）
sudo mkdir -p /home/$USER_NAME/.vnc

sudo x11vnc -storepasswd "$USER_PASS" /home/$USER_NAME/.vnc/passwd
sudo chown $USER_NAME:$USER_NAME /home/$USER_NAME/.vnc/passwd

# 安装 noVNC（网页 VNC 网关）
sudo apt install -y websockify git novnc

# 下载最新 noVNC Web 资源
sudo git clone https://github.com/novnc/noVNC.git /opt/novnc
sudo git clone https://github.com/novnc/websockify /opt/novnc/utils/websockify

# 创建 systemd 服务（自动启动 x11vnc + noVNC）
sudo tee /etc/systemd/system/novnc.service > /dev/null <<EOF
[Unit]
Description=NoVNC Web VNC Server
After=multi-user.target

[Service]
Type=simple
User=$USER_NAME
ExecStart=/bin/bash -c '/usr/bin/x11vnc -forever -shared -rfbauth /home/$USER_NAME/.vnc/passwd -display :0 -auth guess & /opt/novnc/utils/novnc_proxy --vnc localhost:5900 --listen 6080'
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# 启动服务
sudo systemctl daemon-reload
sudo systemctl enable novnc.service
sudo systemctl start novnc.service

echo "####################################################"
echo "🌐 Web VNC 启动成功！请访问以下地址："
echo "👉 http://<服务器IP>:6080/vnc.html"
echo ""
echo "🧑 登录用户：$USER_NAME"
echo "🔐 密码：$USER_PASS"
echo "💻 分辨率：$RESOLUTION（同 MATE 桌面）"
echo "####################################################"

echo "####################################################"
echo " ✅ 部署完成！MATE + X2Go 高峰优化方案已生效"
echo "####################################################"
echo "🔐 用户名：$USER_NAME"
echo "🌐 分辨率：$RESOLUTION"
echo "🟢 客户端建议设置："
echo "    - 模式：ADSL"
echo "    - 压缩：JPEG9"
echo "    - 缓存：32MB"
echo "    - 色彩：16位"
echo "####################################################"