#!/bin/bash
set -e

USER_NAME="admin"
USER_PASS="noneboy"     # 初始用户密码
VNC_PASS="noneboy"     # VNC 连接密码
VNC_PORT=5900
RESOLUTION="1920x1080"

echo "[1/9] 修改用户 $USER_NAME 的密码为 $USER_PASS..."
echo "$USER_NAME:$USER_PASS" | sudo chpasswd


echo "[2/9] 安装 GNOME 桌面环境（ubuntu-desktop）..."
sudo apt update
sudo apt upgrade -y
sudo DEBIAN_FRONTEND=noninteractive apt install -y ubuntu-desktop

echo "[4/9] 安装 x11vnc..."
sudo apt install -y x11vnc
sudo apt install xserver-xorg-video-dummy

sudo tee /etc/X11/xorg.conf <<EOF
Section "Monitor"
    Identifier "Monitor0"
    HorizSync 28.0-80.0
    VertRefresh 48.0-75.0
    Modeline "1920x1080"  173.00  1920 2048 2248 2576  1080 1083 1088 1120 -hsync +vsync
EndSection

Section "Device"
    Identifier "Device0"
    Driver "dummy"
    VideoRam 256000
EndSection

Section "Screen"
    Identifier "Screen0"
    Device "Device0"
    Monitor "Monitor0"
    DefaultDepth 24
    SubSection "Display"
        Depth 24
        Modes "1920x1080"
    EndSubSection
EndSection
EOF

echo "[3/10] 设置 GDM 自动登录为 $USER_NAME..."
# 确保 [daemon] 存在
sudo grep -q "^\[daemon\]" /etc/gdm3/custom.conf || echo "[daemon]" | sudo tee -a /etc/gdm3/custom.conf
# 移除旧配置
sudo sed -i '/^#*AutomaticLoginEnable/d' /etc/gdm3/custom.conf
sudo sed -i '/^#*AutomaticLogin=/d' /etc/gdm3/custom.conf
# 插入新配置
sudo sed -i "/^\[daemon\]/a AutomaticLoginEnable=true\nAutomaticLogin=$USER_NAME\nWaylandEnable=false" /etc/gdm3/custom.conf

echo "[5/9] 配置 VNC 密码..."
sudo -u "$USER_NAME" mkdir -p /home/"$USER_NAME"/.vnc
sudo -u admin x11vnc -storepasswd noneboy /home/admin/.vnc/passwd
sudo chown admin:admin /home/admin/.vnc/passwd
sudo chmod 600 /home/admin/.vnc/passwd

echo "[6/9] 创建 x11vnc systemd 启动服务..."
cat <<EOF | sudo tee /etc/systemd/system/x11vnc.service
[Unit]
Description=Start x11vnc at startup for $USER_NAME
After=multi-user.target graphical.target

[Service]
Type=simple
User=$USER_NAME
ExecStart=/usr/bin/x11vnc -display :0 -auth /run/user/1000/gdm/Xauthority -forever -loop -noxdamage -repeat -rfbauth /home/$USER_NAME/.vnc/passwd -rfbport $VNC_PORT -shared
Restart=on-failure

[Install]
WantedBy=graphical.target
EOF

echo "[7/9] 固定分辨率为 $RESOLUTION..."
cat <<EOF | sudo tee /home/$USER_NAME/.xprofile
#!/bin/bash
export DISPLAY=:0
xrandr --output \$(xrandr | grep ' connected' | cut -d' ' -f1) --mode $RESOLUTION
EOF
sudo chown $USER_NAME:$USER_NAME /home/$USER_NAME/.xprofile
sudo chmod +x /home/$USER_NAME/.xprofile

echo "[8/9] 启用并启动 x11vnc 服务..."
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable x11vnc.service
sudo systemctl restart x11vnc.service

echo "[8/10] 设置 admin 用户自动登录图形界面..."
sudo loginctl enable-linger "$USER_NAME"

echo "[9/10] 检查是否有 display :0 启动，如果没有说明需重启系统..."

if ! sudo loginctl show-session "$(loginctl | grep "$USER_NAME" | awk '{print $1}')" -p Type | grep -q "x11"; then
  echo "[⚠️ ] 未检测到 X 图形会话（DISPLAY=:0），请稍后手动执行：sudo reboot"
else
  echo "[✅] 已检测到图形会话，VNC 服务器可用：端口 $VNC_PORT"
fi

echo "[9/9] 所有设置完成，建议现在重启：sudo reboot"
sudo reboot