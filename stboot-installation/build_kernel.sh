#! /bin/bash

# USAGE
# ./make_kernel.sh <kernel_config_file> <kernel_output_file_name> <kernel_src> <kernel_ver>

set -o errexit
set -o pipefail
set -o nounset
#set -o xtrace

# Set magic variables for current file & dir
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${dir}/../" && pwd)"

# Config variables and arguments

src_cache="${root}/cache/kernel"

kernel_config_file=$1
kernel_config_file_modified="${kernel_config_file}.modified"

kernel_output_file=$2

kernel_version=$3
major=$(echo "${kernel_version}" | head -c1)
kernel_src="https://cdn.kernel.org/pub/linux/kernel/v${major}.x"
kernel_name="linux-${kernel_version}"

kernel_src_tarball="${kernel_src}/${kernel_name}.tar.xz"
kernel_src_signature="${kernel_src}/${kernel_name}.tar.sign"

# ---

# Dev keys for verification process

dev_key_1="torvalds@kernel.org"
dev_key_2="gregkh@kernel.org"
keyring=${src_cache}/gnupg/keyring.gpg

# ---

# Kernel build setup

if [ -f "${src_cache}/${kernel_name}.tar.xz" ]; then
    echo "[INFO]: Using cached sources in $(realpath --relative-to="${root}" "${src_cache}/${kernel_name}.tar.xz")"
else
    echo "[INFO]: Downloading Linux Kernel source files from ${src_cache}/${kernel_name}"
    wget "${kernel_src_tarball}" -P "${src_cache}"
fi

if [ -f "${src_cache}/${kernel_name}.tar.sign" ]; then
    echo "[INFO]: Using cached signature in $(realpath --relative-to="${root}" "${src_cache}/${kernel_name}.tar.sign")"
else
    echo "[INFO]: Downloading Linux Kernel source signature"
    wget "${kernel_src_signature}" -P "${src_cache}"
fi

[ -d "${src_cache}/gnupg" ] || { mkdir "${src_cache}/gnupg"; chmod 700 "${src_cache}/gnupg"; }

if [ -f "${keyring}" ]; then
    echo "[INFO]: Using cached kernel developer keys in $(realpath --relative-to="${root}" "${keyring}")"
else
    echo "[INFO]: Fetching kernel developer keys"
    if ! gpg -v --batch --homedir "${src_cache}/gnupg" --auto-key-locate wkd --locate-keys ${dev_key_1} ${dev_key_2}; then
        exit 1
    fi
    gpg --batch --homedir "${src_cache}/gnupg" --no-default-keyring --export ${dev_key_1} ${dev_key_2} > "${keyring}"
fi

echo "[INFO]: Verifying signature of the kernel tarball"
count=$(xz -cd "${src_cache}/${kernel_name}.tar.xz" \
	   | gpgv --homedir "${src_cache}/gnupg" "--keyring=${keyring}" --status-fd=1 "${src_cache}/${kernel_name}.tar.sign" - \
           | grep -c -E '^\[GNUPG:\] (GOODSIG|VALIDSIG)')
if [[ "${count}" -lt 2 ]]; then
    exit 1
fi
echo
echo "[INFO]: Successfully verified kernel source tarball"

# ---

# Build kernel in cache

echo "[INFO]: Unpacking kernel source tarball"
[ -d "${src_cache}/${kernel_name}" ] && rm -rf "${src_cache:?}/${kernel_name:?}"
tar -xf "${src_cache}/${kernel_name}.tar.xz" -C "${src_cache}"

echo "[INFO]: Building Linuxboot kernel"
if [ -f "${kernel_config_file}.patch" ]; then
    cfg=${kernel_config_file}.patch
elif [ -f "${kernel_config_file}" ]; then
    cfg=${kernel_config_file}
fi
cp "${cfg}" "${src_cache}/${kernel_name}/.config"
cd "${src_cache}/${kernel_name}"
while true; do
    echo "[INFO]: Loaded $(realpath --relative-to="${root}" "${cfg}") as .config:"
    echo "[INFO]: Any config changes you make in menuconfig will be saved to:"
    echo "[INFO]: $(realpath --relative-to="${root}" "${kernel_config_file_modified}")"
    echo "[INFO]: However, it is recommended to just save and exit without modifications."
    read -rp "Press any key to continue" x
    case $x in
        * ) break;;
    esac
done

make menuconfig
make savedefconfig
cp defconfig "${kernel_config_file_modified}"

make "-j$(nproc)"
cd "${dir}"
cp "${src_cache}/${kernel_name}/arch/x86/boot/bzImage" "${kernel_output_file}"

echo ""
echo "Successfully created $(realpath --relative-to="${root}" "${kernel_output_file}") (${kernel_name})"

