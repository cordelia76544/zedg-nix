#!/usr/bin/env bash
set -euo pipefail

# 上游仓库
REPO="x6nux/zed-globalization"
# 要抓取的资产（架构 + 后缀），用于在 release assets 里做匹配
ASSET_PATTERN='linux-x86_64.*\.tar\.gz$'

# 带认证的 curl，避免 API 匿名限流（60 次/小时）
gh_curl() {
  curl -sfL \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} \
    "$@"
}

echo "Checking latest release for $REPO..."

RELEASE=$(gh_curl "https://api.github.com/repos/$REPO/releases/latest") || {
  echo "错误：无法访问 GitHub API（可能被限流，请设置 GITHUB_TOKEN）" >&2
  exit 1
}

LATEST_TAG=$(jq -r '.tag_name' <<<"$RELEASE")
if [ -z "$LATEST_TAG" ] || [ "$LATEST_TAG" == "null" ]; then
  echo "错误：无法解析 tag_name" >&2
  exit 1
fi

# 去掉前缀 'v'，作为 sources.nix 里的 version
VERSION=${LATEST_TAG#v}

# 从现有 sources.nix 提取当前版本号
CURRENT_VERSION=$(grep 'version =' sources.nix | awk -F '"' '{print $2}')

if [ "$VERSION" == "$CURRENT_VERSION" ]; then
  echo "Already up to date ($VERSION)."
  exit 0
fi

echo "Updating from $CURRENT_VERSION to $VERSION..."

# 关键点：不要用 tag 拼文件名。
# 上游在同一上游版本重发时会给 tag 加后缀（如 tag v1.18.1.1 里的文件仍叫 ...-v1.18.1.tar.gz），
# 所以直接从 release assets 里取真实的下载地址。
URL=$(jq -r --arg p "$ASSET_PATTERN" \
  '.assets[] | select(.name | test($p)) | .browser_download_url' <<<"$RELEASE" | head -n1)

if [ -z "$URL" ]; then
  echo "错误：在 $LATEST_TAG 中找不到匹配 $ASSET_PATTERN 的资产。现有资产：" >&2
  jq -r '.assets[].name' <<<"$RELEASE" >&2
  exit 1
fi

ASSET_NAME=$(basename "$URL")
echo "Found asset: $ASSET_NAME"

# 优先从 release 附带的 sha256sums.txt 取哈希，避免下载 ~150MB
SRI_HASH=""
SUMS_URL=$(jq -r '.assets[] | select(.name == "sha256sums.txt") | .browser_download_url' <<<"$RELEASE" | head -n1)

if [ -n "$SUMS_URL" ]; then
  echo "Fetching hash from sha256sums.txt..."
  HEX_HASH=$(curl -sfL "$SUMS_URL" | awk -v n="$ASSET_NAME" '$2 == n || $2 == "*"n {print $1; exit}') || true
  if [ -n "${HEX_HASH:-}" ]; then
    # 新版 Nix 用 nix hash convert，旧版回退到 nix hash to-sri
    SRI_HASH=$(nix hash convert --hash-algo sha256 --to sri "$HEX_HASH" 2>/dev/null \
      || nix hash to-sri --type sha256 "$HEX_HASH")
  fi
fi

# 回退：sha256sums.txt 不存在或没匹配上时，老老实实下载
if [ -z "$SRI_HASH" ]; then
  echo "Falling back to nix-prefetch-url for $URL..."
  RAW_HASH=$(nix-prefetch-url --type sha256 "$URL")
  SRI_HASH=$(nix hash convert --hash-algo sha256 --to sri "$RAW_HASH" 2>/dev/null \
    || nix hash to-sri --type sha256 "$RAW_HASH")
fi

echo "Hash: $SRI_HASH"

# 重新生成 sources.nix
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
