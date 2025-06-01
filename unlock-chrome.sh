#!/bin/bash

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}>>> 启动 Chrome 并清理锁文件${NC}"

# 配置目录
DEFAULT_PROFILE="$HOME/.config/google-chrome/Default"
CUSTOM_PROFILE="$HOME/ChromeDebug"

LOCK_FILES=("SingletonLock" "SingletonSocket" "SingletonCookie")

clean_profile_locks() {
    local DIR="$1"
    if [ -d "$DIR" ]; then
        for file in "${LOCK_FILES[@]}"; do
            rm -f "$DIR/$file" 2>/dev/null && \
            echo -e "${RED}⚠️ 删除锁定文件: $DIR/$file${NC}"
        done
    fi
}

clean_profile_locks "$DEFAULT_PROFILE"
clean_profile_locks "$CUSTOM_PROFILE"
