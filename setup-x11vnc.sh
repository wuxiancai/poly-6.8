#!/bin/bash
set -e

USER_NAME="admin"
USER_PASS="admin"     # 初始用户密码
VNC_PASS="123456"     # VNC 连接密码
VNC_PORT=5900
RESOLUTION="1920x1080"

echo "[1/9] 创建用户 $USER_NAME（如已存在将跳过）..."
if ! id "$USER_NAME" &>/dev/null; then
  sudo adduser --disabled-password --gecos "" "$USER_NAME"
  echo "$USER_NAME:$USER_PASS" | sudo chpasswd
  sudo usermod -aG sudo "$USER_NAME"
fi

echo "[2/9] 安装 GNOME 桌面环境（ubuntu-desktop）..."
sudo apt update
sudo apt upgrade -y
sudo DEBIAN_FRONTEND=noninteractive apt install -y ubuntu-desktop

echo "[3/9] 设置 GDM 自动登录为 $USER_NAME..."
sudo sed -i 's/^#*AutomaticLoginEnable.*/AutomaticLoginEnable=true/' /etc/gdm3/custom.conf
sudo sed -i "s/^#*AutomaticLogin.*/AutomaticLogin=${USER_NAME}/" /etc/gdm3/custom.conf

echo "[4/9] 安装 x11vnc..."
sudo apt install -y x11vnc

echo "[5/9] 配置 VNC 密码..."
sudo -u "$USER_NAME" mkdir -p /home/"$USER_NAME"/.vnc
sudo -u "$USER_NAME" bash -c "echo '$VNC_PASS' | x11vnc -storepasswd stdin /home/$USER_NAME/.vnc/passwd"
sudo chown -R "$USER_NAME":"$USER_NAME" /home/"$USER_NAME"/.vnc

echo "[6/9] 创建 x11vnc systemd 启动服务..."
cat <<EOF | sudo tee /etc/systemd/system/x11vnc.service
[Unit]
Description=Start x11vnc at startup for $USER_NAME
After=multi-user.target graphical.target

[Service]
Type=simple
User=$USER_NAME
ExecStart=/usr/bin/x11vnc -auth guess -forever -loop -noxdamage -repeat -rfbauth /home/$USER_NAME/.vnc/passwd -rfbport $VNC_PORT -shared -display :0
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

echo "[9/9] 所有设置完成，建议现在重启：sudo reboot"
sudo reboot