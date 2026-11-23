#!/usr/bin/env bash
# 准备 Linux 桌面端构建依赖。
#
# 背景一：密码存储用 flutter_secure_storage，它在 Linux 上通过 libsecret 访问系统
# 密钥环（Secret Service）。编译期需要 libsecret-1 的开发头文件与 pkg-config
# 文件（libsecret-1-dev），运行期只需要系统已有的运行库。
# 没有 root 权限时，本脚本把 .deb 里的开发文件解包到 `.desktop-deps/`
# （已在 .gitignore 中忽略），改写 .pc 里的 prefix，再通过 PKG_CONFIG_PATH
# 让 CMake 找到它们 —— 不改动系统目录、不需要 root。
#
# 背景二：Flutter 的 native assets 编译会用 clang++ 所在目录去找链接器
# （ld.lld / ld）。部分发行版的 clang 包只装编译器、不装 lld（如 Ubuntu 的
# clang-18），会让 `flutter build linux` 直接失败。本脚本会生成一个 clang++
# 包装脚本目录（.desktop-deps/toolchain），补齐 clang / llvm-ar / ld。
#
# 用法：
#   scripts/setup_linux_deps.sh            # 有 sudo 时装系统包，否则提示
#   scripts/setup_linux_deps.sh --local    # 强制解包到 .desktop-deps/
#   eval "$(scripts/setup_linux_deps.sh --print-env)"   # 打印需要 export 的变量
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPS_DIR="${ROOT_DIR}/.desktop-deps"
PKG_DIR="${DEPS_DIR}/usr/lib/x86_64-linux-gnu/pkgconfig"
TOOLCHAIN_DIR="${DEPS_DIR}/toolchain"
MODE="${1:-auto}"

log() { printf '[linux-deps] %s\n' "$*" >&2; }

print_env() {
  if [ -d "${PKG_DIR}" ]; then
    printf 'export PKG_CONFIG_PATH="%s${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"\n' "${PKG_DIR}"
    # pkg-config 产出的 -lsecret-1 需要能解析到本地 .so 符号链接。
    printf 'export LIBRARY_PATH="%s${LIBRARY_PATH:+:$LIBRARY_PATH}"\n' \
      "${DEPS_DIR}/usr/lib/x86_64-linux-gnu"
  fi
  if [ -d "${TOOLCHAIN_DIR}" ]; then
    printf 'export PATH="%s:$PATH"\n' "${TOOLCHAIN_DIR}"
  fi
}

if [ "${MODE}" = "--print-env" ]; then
  print_env
  exit 0
fi

# ---------------------------------------------------------------------------
# clang 工具链 shim
# ---------------------------------------------------------------------------
prepare_toolchain_shim() {
  local clangpp clangpp_real clang_dir ar ld
  # 注意：不要把 clang++ 解析成 clang —— 驱动模式由 argv[0] 决定，
  # 包装脚本必须 exec 真正的 clang++（否则 C++ 标准库不入链接命令）。
  clangpp="$(command -v clang++ 2>/dev/null || true)"
  [ -n "${clangpp}" ] || return 0
  clangpp_real="$(readlink -f "${clangpp}")"
  clang_dir="$(dirname "${clangpp_real}")"
  # 编译器目录里已经有链接器时不用处理。
  if [ -x "${clang_dir}/ld" ] || [ -x "${clang_dir}/ld.lld" ]; then
    return 0
  fi
  mkdir -p "${TOOLCHAIN_DIR}"
  {
    echo '#!/usr/bin/env bash'
    echo '# 由 scripts/setup_linux_deps.sh 生成的包装脚本（不要提交）。'
    echo "exec \"${clangpp}\" \"\$@\""
  } > "${TOOLCHAIN_DIR}/clang++"
  chmod +x "${TOOLCHAIN_DIR}/clang++"
  ln -sfn "${clangpp_real}" "${TOOLCHAIN_DIR}/clang"
  ar="$(command -v llvm-ar 2>/dev/null || command -v ar)"
  ld="$(command -v ld.lld 2>/dev/null || command -v ld)"
  [ -n "${ar}" ] && ln -sfn "$(readlink -f "${ar}")" "${TOOLCHAIN_DIR}/llvm-ar"
  [ -n "${ld}" ] && ln -sfn "$(readlink -f "${ld}")" "${TOOLCHAIN_DIR}/ld"
  log "已生成 clang 工具链 shim：${TOOLCHAIN_DIR}（补齐 clang / llvm-ar / ld）"
}

prepare_toolchain_shim

# 系统已装开发包时无需再下载 libsecret。
if pkg-config --exists libsecret-1 2>/dev/null; then
  log "已检测到系统 libsecret-1（$(pkg-config --modversion libsecret-1)），无需额外下载。"
  print_env >&2
  exit 0
fi

if [ "${MODE}" = "auto" ]; then
  cat >&2 <<'EOF'
[linux-deps] 未找到 libsecret-1 的开发文件（pkg-config 无法解析 libsecret-1）。
[linux-deps] 推荐用系统包管理器安装（需要 root）：
[linux-deps]     Debian/Ubuntu: sudo apt install libsecret-1-dev
[linux-deps]     Fedora:        sudo dnf install libsecret-devel
[linux-deps]     Arch:          sudo pacman -S libsecret
[linux-deps] 没有 root 权限时执行 `scripts/setup_linux_deps.sh --local`
[linux-deps] 把开发文件解包到 .desktop-deps/（不改动系统目录）。
EOF
  if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    log "检测到可用的 sudo，开始安装 libsecret-1-dev …"
    sudo apt-get install -y libsecret-1-dev
    exit 0
  fi
  exit 1
fi

if [ "${MODE}" != "--local" ]; then
  log "未知参数：${MODE}（可用：--local / --print-env）"
  exit 2
fi

# ---------------------------------------------------------------------------
# 本地解包模式（Debian/Ubuntu）
# ---------------------------------------------------------------------------
command -v apt-get >/dev/null 2>&1 || {
  log "本地解包模式依赖 apt-get（Debian/Ubuntu）；其他发行版请用系统包管理器安装 libsecret-devel。"
  exit 1
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT
mkdir -p "${PKG_DIR}"

# libsecret-1.pc 的 Requires 递归引用了 libgcrypt 与 gpg-error，
# 三者的 .pc 都必须能被 pkg-config 解析。
for package in libsecret-1-dev libgcrypt20-dev libgpg-error-dev; do
  log "下载 ${package} …"
  ( cd "${TMP_DIR}" && apt-get download -qq "${package}" ) || {
    log "下载 ${package} 失败，请检查网络或 apt 源。"
    exit 1
  }
  deb="$(ls -1 "${TMP_DIR}/${package}"_*.deb | head -n1)"
  dpkg-deb -x "${deb}" "${TMP_DIR}/root"
done

# 只取出头文件、pkg-config 文件与 *.so 符号链接，运行库本身仍用系统的。
# 少了 libsecret-1.so 这条链接，链接器会报「找不到 -lsecret-1」。
mkdir -p "${DEPS_DIR}/usr"
cp -a "${TMP_DIR}/root/usr/include" "${DEPS_DIR}/usr/include" 2>/dev/null || true
libdir_host="${DEPS_DIR}/usr/lib/x86_64-linux-gnu"
mkdir -p "${libdir_host}"
cp -a "${TMP_DIR}"/root/usr/lib/*/pkgconfig/*.pc "${PKG_DIR}/" 2>/dev/null || true
# 这些 .so 只是链接期用的符号链接，真实运行库在系统里；
# 目标不在本地目录时必须改指系统的绝对路径，否则链接器解析不到。
for so in "${TMP_DIR}"/root/usr/lib/*/*.so; do
  [ -L "${so}" ] || continue
  so_name="$(basename "${so}")"
  so_target="$(readlink "${so}")"
  if [ ! -e "${libdir_host}/${so_target}" ] && [ ! -e "${TMP_DIR}/root/usr/lib/x86_64-linux-gnu/${so_target}" ]; then
    so_target="/usr/lib/x86_64-linux-gnu/${so_target}"
  fi
  ln -sfn "${so_target}" "${libdir_host}/${so_name}"
done

# 把 .pc 里的 /usr 前缀改写到 .desktop-deps，避免指向不存在的系统头文件。
while IFS= read -r -d '' pc; do
  sed -i "s|^prefix=/usr$|prefix=${DEPS_DIR}/usr|; s|^exec_prefix=/usr$|exec_prefix=${DEPS_DIR}/usr|" "${pc}"
done < <(find "${PKG_DIR}" -name '*.pc' -print0)

PKG_CONFIG_PATH="${PKG_DIR}" pkg-config --exists libsecret-1 || {
  log "解包后 pkg-config 仍无法解析 libsecret-1，请改用系统包管理器安装。"
  exit 1
}

log "完成（libsecret-1 $(PKG_CONFIG_PATH="${PKG_DIR}" pkg-config --modversion libsecret-1)）。构建/运行前设置："
print_env >&2
