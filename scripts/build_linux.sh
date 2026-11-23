#!/usr/bin/env bash
# 一键构建 Linux 桌面端（依赖准备 → 构建 → 打印产物路径）。
#
# 用法：
#   scripts/build_linux.sh              # release 构建（默认）
#   scripts/build_linux.sh --debug      # debug 构建
#   scripts/build_linux.sh --bundle     # 额外把产物打成 dist/pie-note-linux-<arch>.tar.gz
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="release"
BUNDLE=0

for arg in "$@"; do
  case "${arg}" in
    --debug) MODE="debug" ;;
    --release) MODE="release" ;;
    --bundle) BUNDLE=1 ;;
    -h|--help)
      sed -n '2,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      printf '[build-linux] 未知参数：%s\n' "${arg}" >&2
      exit 2
      ;;
  esac
done

cd "${ROOT_DIR}"

# 依赖：libsecret 开发文件 + clang 链接器 shim。
"${ROOT_DIR}/scripts/setup_linux_deps.sh" >/dev/null 2>&1 || true
# shellcheck disable=SC2046
eval "$("${ROOT_DIR}/scripts/setup_linux_deps.sh" --print-env)"

printf '[build-linux] flutter build linux --%s\n' "${MODE}"
flutter "build" "linux" "--${MODE}"

BUNDLE_DIR="${ROOT_DIR}/build/linux/x64/${MODE}/bundle"
printf '[build-linux] 产物：%s\n' "${BUNDLE_DIR}"

if [ "${BUNDLE}" -eq 1 ]; then
  mkdir -p "${ROOT_DIR}/dist"
  ARCHIVE="${ROOT_DIR}/dist/pie-note-linux-x64-${MODE}.tar.gz"
  tar -czf "${ARCHIVE}" -C "$(dirname "${BUNDLE_DIR}")" "$(basename "${BUNDLE_DIR}")"
  printf '[build-linux] 归档：%s\n' "${ARCHIVE}"
fi
