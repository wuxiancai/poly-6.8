#!/bin/bash
set -e

USER_NAME="admin"
USER_PASS="noneboy"
USER_HOME="/home/$USER_NAME"

echo "📌 创建用户 $USER_NAME..."
if ! id "$USER_NAME" &>/dev/null; then
  adduser --disabled-password --gecos "" "$USER_NAME"
fi
echo "$USER_NAME:$USER_PASS" | chpasswd

echo "📌 安装依赖..."
apt update
apt install -y tigervnc-standalone-server tigervnc-xorg-extension \
  websockify python3-numpy git lxde x11-utils \
  xserver-xorg-video-dummy dbus-x11 dbus-user-session xrdp

echo "📌 设置虚拟显示器分辨率..."
mkdir -p /etc/X11/xorg.conf.d
cat >/etc/X11/xorg.conf.d/10-headless.conf <<'EOF'
Section "Monitor"
    Identifier  "DummyMonitor"
    HorizSync   30.0-150.0
    VertRefresh 50.0-100.0
    Modeline    "1920x1080_60.00"  173.00  1920 2048 2248 2576 1080 1083 1088 1120 -hsync +vsync
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
        Modes "1920x1080_60.00"
        Virtual 1920 1080
    EndSubSection
EndSection
EOF

echo "📌 配置 admin 用户 VNC..."
runuser -l "$USER_NAME" -c "
mkdir -p ~/.vnc ~/.config/autostart ~/.dbus
dbus-uuidgen > ~/.dbus/machine-id

echo 'geometry=1920x1080
depth=24
localhost
alwaysshared' > ~/.vnc/config

echo '$USER_PASS' | vncpasswd -f > ~/.vnc/passwd
chmod 600 ~/.vnc/passwd

cat > ~/.vnc/xstartup <<'EOS'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
eval \"\$(dbus-launch --sh-syntax --exit-with-session)\"
export XKL_XMODMAP_DISABLE=1
exec startlxde > ~/.vnc/xstartup.log 2>&1
EOS
chmod +x ~/.vnc/xstartup

cat > ~/.config/autostart/resolution.desktop <<'EOS'
[Desktop Entry]
Type=Application
Name=Resolution Setup
Exec=sh -c 'xrandr --newmode "1920x1080_60.00" 173.00 1920 2048 2248 2576 1080 1083 1088 1120 -hsync +vsync && xrandr --addmode $(xrandr -q | awk "/ connected/ {print \$1; exit}") "1920x1080_60.00" && xrandr --output $(xrandr -q | awk "/ connected/ {print \$1; exit}") --mode "1920x1080_60.00"'
X-GNOME-Autostart-enabled=true
EOS
"

echo "📌 创建 VNC systemd 服务..."
cat >/etc/systemd/system/vncserver.service <<EOF
[Unit]
Description=TigerVNC Server for $USER_NAME
After=network.target

[Service]
Type=simple
User=$USER_NAME
WorkingDirectory=$USER_HOME
ExecStartPre=/bin/sh -c 'rm -f /tmp/.X1-lock'
ExecStart=/usr/bin/vncserver :1 -fg
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

echo "📌 安装并配置 noVNC..."
[ -d $USER_HOME/noVNC ] || runuser -l "$USER_NAME" -c "git clone https://github.com/novnc/noVNC.git ~/noVNC"
cp "$USER_HOME/noVNC/vnc.html" "$USER_HOME/noVNC/index.html"

cat >/etc/systemd/system/novnc.service <<EOF
[Unit]
Description=noVNC WebSocket Proxy
After=network.target vncserver.service

[Service]
Type=simple
User=$USER_NAME
WorkingDirectory=$USER_HOME/noVNC
ExecStart=/usr/bin/websockify --web ./ 6080 localhost:5901
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

echo "📌 启动并启用 VNC 和 noVNC..."
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable vncserver novnc
systemctl restart vncserver novnc

echo "📌 配置 XRDP 转发到 VNC..."
sed -i '/^\[Xorg\]/a\
\
[xrdp-vnc]\
name=Shared-VNC-Session\
lib=libvnc.so\
ip=127.0.0.1\
port=5901\
username='$USER_NAME'\
password='$USER_PASS'
' /etc/xrdp/xrdp.ini

systemctl enable xrdp
systemctl restart xrdp

echo "📌 开启防火墙端口..."
ufw allow 3389/tcp || true

echo "📌 设置初次分辨率..."
until DISPLAY=:1 xrandr -q &>/dev/null; do sleep 1; done
OUTPUT=$(DISPLAY=:1 xrandr | awk '/ connected/ {print $1; exit}')
DISPLAY=:1 xrandr --newmode "1920x1080_60.00" 173.00 1920 2048 2248 2576 1080 1083 1088 1120 -hsync +vsync
DISPLAY=:1 xrandr --addmode "$OUTPUT" "1920x1080_60.00"
DISPLAY=:1 xrandr --output "$OUTPUT" --mode "1920x1080_60.00"

echo "✅ 安装完成！"
echo "🌐 浏览器访问: http://$(curl -s ifconfig.me):6080"
echo "🪟 Windows 远程桌面访问: $(curl -s ifconfig.me):3389"