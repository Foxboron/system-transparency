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

kernel_config=$1
kernel_config_modified="${kernel_config}.modified"
kernel=$2
out="$(dirname "${kernel}")"
kernel_backup="${kernel}.backup"
version=$3
major=$(echo "${version}" | head -c1)
src_url="https://cdn.kernel.org/pub/linux/kernel/v${major}.x"
version_dir="linux-${version}"
tarball="${src_url}/${version_dir}.tar.xz"
signature="${src_url}/${tarball}.tar.sign"
cache="${root}/cache/kernel"

dev_key_1="torvalds@kernel.org"
dev_key_2="gregkh@kernel.org"
keyring=${cache}/gnupg/keyring.gpg

if [ -f "${kernel}" ]; then
    echo
    echo "[INFO]: backup existing kernel to $(realpath --relative-to="${root}" "${kernel_backup}")"
    mv "${kernel}" "${kernel_backup}"
fi

if [ ! -d "${out}" ]; then mkdir -p "${out}"; fi

if [ -d "${cache}/${version_dir}" ]; then
    echo
    echo "[INFO]: Using cached sources in $(realpath --relative-to="${root}" "${cache}/${version_dir}")"
else
    # sources
    echo "[INFO]: Downloading Linux Kernel source files from ${cache}/${version_dir}"
    rm -f "${tarball}"
    wget "${tarball}" -P "${cache}"
    # signature
    if [ -f "${cache}/${version_dir}.tar.sign" ]; then
        echo "[INFO]: Using cached signature in $(realpath --relative-to="${root}" "${cache}/${version_dir}.tar.sign")"
    else
        echo "[INFO]: Downloading Linux Kernel source signature"
        wget "${signature}" -P "${cache}"
    fi
    # developer keys
    [ -d "${cache}/gnupg" ] || { mkdir "${cache}/gnupg"; chmod 700 "${cache}/gnupg"; }
    if [ -f "${keyring}" ]; then
        echo "[INFO]: Using cached kernel developer keys in $(realpath --relative-to="${root}" "${keyring}")"
    else
        echo "[INFO]: Fetching kernel developer keys"
    if ! gpg -v --batch --homedir "${cache}/gnupg" --auto-key-locate wkd --locate-keys ${dev_key_1} ${dev_key_2}; then
        exit 1
    fi
        gpg --batch --homedir "${cache}/gnupg" --no-default-keyring --export ${dev_key_1} ${dev_key_2} > "${keyring}"
    fi
    # verification
    echo "[INFO]: Verifying signature of the kernel tarball"
    count=$(xz -cd "${cache}/${version_dir}.tar.xz" \
	    | gpgv --homedir "${cache}/gnupg" "--keyring=${keyring}" --status-fd=1 "${cache}/${version_dir}.tar.sign" - \
        | grep -c -E '^\[GNUPG:\] (GOODSIG|VALIDSIG)')
    if [[ "${count}" -lt 2 ]]; then
        rm -rf "${cache:?b}/${version_dir}" "${tarball}"
        exit 1
    fi
    echo
    echo "[INFO]: Successfully verified kernel sources"
    echo "[INFO]: Unpacking kernel source tarball"
    [ -d "${cache}/${version_dir}" ] && rm -rf "${cache:?}/${version_dir:?}"
    tar -xf "${cache}/${version_dir}.tar.xz" -C "${cache}"
fi

# Build kernel in cache
echo "[INFO]: Building Linuxboot kernel"
if [ -f "${kernel_config}.patch" ]; then
    cfg=${kernel_config}.patch
elif [ -f "${kernel_config}" ]; then
    cfg=${kernel_config}
fi

cp "${cfg}" "${cache}/${version_dir}/.config"
cd "${cache}/${version_dir}"
while true; do
    echo
    echo "[INFO]: Loaded $(realpath --relative-to="${root}" "${cfg}") as .config:"
    echo "[INFO]: Any config changes you make in menuconfig will be saved to:"
    echo "[INFO]: $(realpath --relative-to="${root}" "${kernel_config_modified}")"
    echo "[INFO]: However, it is recommended to just save and exit without modifications."
    read -rp "Press any key to continue" x
    case $x in
        * ) break;;
    esac
done

make menuconfig
make savedefconfig
cp defconfig "${kernel_config_modified}"

make "-j$(nproc)"
cd "${dir}"
cp "${cache}/${version_dir}/arch/x86/boot/bzImage" "${kernel}"

echo ""
echo "Successfully created $(realpath --relative-to="${root}" "${kernel}") (${version})"


