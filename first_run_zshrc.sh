#!/bin/zsh

if [ -f ~/.zshrc ]; then
    # 检查是否已经设置了这些代理
    if ! grep -q "export https_proxy=" ~/.zshrc; then
        echo '# 设置代理' >> ~/.zshrc
        echo 'export https_proxy="http://127.0.0.1:7890"' >> ~/.zshrc
        echo 'export http_proxy="http://127.0.0.1:7890"' >> ~/.zshrc
        echo 'export no_proxy="localhost,local,127.0.0.1,::1"' >> ~/.zshrc
    fi
else
    # 如果文件不存在，创建新文件
    cat > ~/.zshrc << 'EOL'
# 设置代理
export https_proxy="http://127.0.0.1:7890"
export http_proxy="http://127.0.0.1:7890"
export no_proxy="localhost,local,127.0.0.1,::1"
EOL
fi
source ~/.zshrc
# 在 HOSTS 文件中添加 github.com 和 raw.githubusercontent.com 的记录
echo "185.199.108.153 raw.githubusercontent.com" | sudo tee -a /etc/hosts
echo "185.199.109.153 raw.githubusercontent.com" | sudo tee -a /etc/hosts
echo "185.199.110.153 raw.githubusercontent.com" | sudo tee -a /etc/hosts
echo "185.199.111.153 raw.githubusercontent.com" | sudo tee -a /etc/hosts