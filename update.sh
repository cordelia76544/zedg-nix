#!/usr/bin/env bash
set -euo pipefail

# 上游仓库
REPO="x6nux/zed-globalization"

echo "Checking latest release for $REPO..."
# 获取最新 tag (例如 v1.9.0)
LATEST_TAG=$(curl -s "https://api.github.com/repos/$REPO/releases/latest" | jq -r .tag_name)
# 去除版本号前面的 'v'
VERSION=${LATEST_TAG#v}

# 从现有的 sources.nix 中提取当前版本号
CURRENT_VERSION=$(grep 'version =' sources.nix | awk -F '"' '{print $2}')

if [ "$VERSION" == "$CURRENT_VERSION" ]; then
  echo "Already up to date ($VERSION)."
  exit 0
fi

echo "Updating from $CURRENT_VERSION to $VERSION..."

# 构造新的下载链接
URL="https://github.com/x6nux/zed-globalization/releases/download/${LATEST_TAG}/zedg-zh-cn-linux-x86_64-${LATEST_TAG}.tar.gz"

echo "Prefetching hash for $URL..."
# 使用 nix-prefetch-url 获取原始 sha256，然后转换为 SRI 格式
RAW_HASH=$(nix-prefetch-url --type sha256 "$URL")
SRI_HASH=$(nix hash to-sri --type sha256 "$RAW_HASH")

# 重新生成 sources.nix 文件
cat <<EOF > sources.nix
{
  version = "$VERSION";

  x86_64-linux = {
    url = "$URL";
    hash = "$SRI_HASH";
  };
}
EOF

echo "sources.nix updated successfully."