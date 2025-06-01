#!/bin/bash
set -e

# 清理旧配置
rm -rf ~/.vnc
sudo rm -f /etc/systemd/system/vncserver.service /etc/systemd/system/novnc.service

# 创建必要目录
mkdir -p ~/.vnc ~/.config/autostart
sudo mkdir -p /etc/X11/xorg.conf.d

# 安装依赖
sudo apt update
sudo apt install -y tigervnc-standalone-server tigervnc-xorg-extension \
    websockify python3-numpy git xfce4 xfce4-goodies \
    x11-utils xserver-xorg-video-dummy \
    dbus-x11 dbus-user-session xfce4-settings

# 配置用户级 DBus
mkdir -p ~/.dbus
dbus-uuidgen > ~/.dbus/machine-id

# 创建VNC配置文件
cat <<EOF > ~/.vnc/config
geometry=1920x1080
depth=24
localhost
alwaysshared
EOF

# 设置VNC密码
echo "请设置VNC连接密码（至少6位）："
vncpasswd

# 创建启动脚本
cat <<EOF > ~/.vnc/xstartup
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
eval "\$(dbus-launch --sh-syntax --exit-with-session)"
export XKL_XMODMAP_DISABLE=1
exec startxfce4
EOF
chmod +x ~/.vnc/xstartup

# 创建虚拟显示配置（修正版）
sudo tee /etc/X11/xorg.conf.d/10-headless.conf <<'EOF'
Section "Monitor"
    Identifier  "DummyMonitor"
    HorizSync   30.0-150.0
    VertRefresh 50.0-100.0
    Modeline    "1920x1080_60.00"  173.00  1920 2048 2248 2576  1080 1083 1088 1120 -hsync +vsync  # 更新Modeline
EndSection

Section "Device"
    Identifier  "DummyDevice"
    Driver      "dummy"
    VideoRam    256000
    Option      "IgnoreEDID" "true"
EndSection

Section "Screen"
    Identifier  "DummyScreen"
    Device      "DummyDevice"
    Monitor     "DummyMonitor"
    DefaultDepth 24
    SubSection "Display"
        Depth 24
        Modes "1920x1080_60.00"  # 更新分辨率模式
        Virtual 1920 1080        # 更新虚拟分辨率
    EndSubSection
EndSection
EOF

# 安装noVNC
[ -d ~/noVNC ] || git clone https://github.com/novnc/noVNC.git ~/noVNC
cp ~/noVNC/vnc.html ~/noVNC/index.html

# 创建系统服务
sudo bash -c "cat > /etc/systemd/system/vncserver.service" <<EOF
[Unit]
Description=TigerVNC Server
After=network.target

[Service]
Type=simple
User=$(whoami)
WorkingDirectory=$HOME
ExecStartPre=/bin/sh -c 'rm -f /tmp/.X1-lock'
ExecStart=/usr/bin/vncserver :1 -fg
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo bash -c "cat > /etc/systemd/system/novnc.service" <<EOF
[Unit]
Description=noVNC Service
After=network.target vncserver.service

[Service]
Type=simple
User=$(whoami)
WorkingDirectory=$HOME/noVNC
ExecStart=/usr/bin/websockify --web ./ 6080 localhost:5901
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 创建自动分辨率配置
cat <<EOF > ~/.config/autostart/resolution.desktop
[Desktop Entry]
Type=Application
Name=Resolution Setup
Exec=sh -c 'xrandr --newmode "1920x1080_60.00" 173.00 1920 2048 2248 2576 1080 1083 1088 1120 -hsync +vsync && xrandr --addmode \$(xrandr -q | awk "/ connected/ {print \\\$1; exit}") "1920x1080_60.00" && xrandr --output \$(xrandr -q | awk "/ connected/ {print \\\$1; exit}") --mode "1920x1080_60.00"'
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF

# 启用服务
sudo systemctl daemon-reload
sudo systemctl enable vncserver novnc
sudo systemctl restart vncserver novnc

# 首次应用分辨率配置
sleep 5
OUTPUT_NAME=$(DISPLAY=:1 xrandr -q | awk '/ connected/ {print $1; exit}')
DISPLAY=:1 xrandr --newmode "1920x1080_60.00" 173.00 1920 2048 2248 2576 1080 1083 1088 1120 -hsync +vsync  # 更新
DISPLAY=:1 xrandr --addmode "$OUTPUT_NAME" "1920x1080_60.00"  # 更新
DISPLAY=:1 xrandr --output "$OUTPUT_NAME" --mode "1920x1080_60.00"

echo "安装完成！访问地址：http://$(curl -s ifconfig.me):6080"