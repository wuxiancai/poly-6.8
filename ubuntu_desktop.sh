#!/bin/bash
set -e

USER_NAME="admin"
VNC_PORT=5900
VNC_PASS="noneboy"  # 可自定义
RESOLUTION="1920x1080"

echo "[1/7] 确保用户 $USER_NAME 存在..."
if ! id "$USER_NAME" &>/dev/null; then
  sudo adduser --gecos "" "$USER_NAME"
  echo "$USER_NAME:$USER_NAME" | sudo chpasswd
  echo "✅ 已创建用户 $USER_NAME"
fi

echo "[2/7] 设置 GDM 自动登录..."
sudo sed -i 's/^#*AutomaticLoginEnable.*/AutomaticLoginEnable=true/' /etc/gdm3/custom.conf
sudo sed -i "s/^#*AutomaticLogin.*/AutomaticLogin=${USER_NAME}/" /etc/gdm3/custom.conf

echo "[3/7] 安装 x11vnc..."
sudo apt update
sudo apt install -y x11vnc

echo "[4/7] 配置 VNC 密码..."
sudo -u "$USER_NAME" mkdir -p /home/"$USER_NAME"/.vnc
sudo -u "$USER_NAME" bash -c "echo '$VNC_PASS' | x11vnc -storepasswd stdin /home/$USER_NAME/.vnc/passwd"
sudo chown -R "$USER_NAME":"$USER_NAME" /home/"$USER_NAME"/.vnc

echo "[5/7] 创建 systemd 启动服务..."
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

echo "[6/7] 设置分辨率 $RESOLUTION（添加 .xprofile）"
cat <<EOF | sudo tee /home/$USER_NAME/.xprofile
#!/bin/bash
xrandr --output \$(xrandr | grep ' connected' | cut -d' ' -f1) --mode $RESOLUTION
EOF
sudo chown $USER_NAME:$USER_NAME /home/$USER_NAME/.xprofile
sudo chmod +x /home/$USER_NAME/.xprofile

echo "[7/7] 启用并启动服务..."
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable x11vnc.service
sudo systemctl restart x11vnc.service

echo "✅ 配置完成，重启后生效：sudo reboot"
sudo reboot