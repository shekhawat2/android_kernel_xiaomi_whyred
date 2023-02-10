#!/usr/bin/env bash
set -e
blue='\033[0;34m'
cyan='\033[0;36m'
yellow='\033[0;33m'
red='\033[0;31m'
nocol='\033[0m'

setup_env() {
    export KERNEL_DIR=${PWD}
    export KBUILD_BUILD_USER="Shekhawat2"
    export KBUILD_BUILD_HOST="Builder"
    export ARCH=arm64
    export CLANG_DIR=${KERNEL_DIR}/../clang-builds
    export OUT_DIR=${KERNEL_DIR}/out
    export ANYKERNEL_DIR=${KERNEL_DIR}/../anykernel
    export JOBS="$(grep -c '^processor' /proc/cpuinfo)"
    export BSDIFF=${KERNEL_DIR}/bin/bsdiff
    export BUILD_TIME=$(date +"%Y%m%d-%H%M%S")
    export KERNELZIP=KCUFKernel-whyred-4.19-${BUILD_TIME}.zip
    export BUILTIMAGE=${OUT_DIR}/arch/arm64/boot/Image
    export BUILTDTB=${OUT_DIR}/arch/arm64/boot/dts/vendor/qcom/whyred.dtb
    export BUILTFSTABDTB=${OUT_DIR}/arch/arm64/boot/dts/vendor/qcom/whyred_fstab.dtb
    export BSDIFF=${KERNEL_DIR}/bin/bsdiff

    if [ ! -d $CLANG_DIR ]; then
        echo "clang directory does not exists, cloning now..."
        git clone https://gitlab.com/shekhawat2/clang-builds.git -b master ${CLANG_DIR} --depth 1
    fi
    if [ ! -d $ANYKERNEL_DIR ]; then
        echo "anykernel directory does not exists, cloning now..."
        git clone https://github.com/shekhawat2/AnyKernel3.git -b whyred_419 ${ANYKERNEL_DIR}
    fi

    export PATH=${CLANG_DIR}/bin:${KERNEL_DIR}/bin:${PATH}
    export KBUILD_COMPILER_STRING=$(${CLANG_DIR}/bin/clang --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')
}

clean_up() {
    echo -e "${cyan}Cleaning Up ${nocol}"
    rm -rf ${ANYKERNEL_DIR}/Image* ${ANYKERNEL_DIR}/kernel_dtb*
    rm -rf ${ANYKERNEL_DIR}/*.xz ${ANYKERNEL_DIR}/*.zip
    rm -rf ${ANYKERNEL_DIR}/bspatch && mkdir -p ${ANYKERNEL_DIR}/bspatch
}

build() {
    BUILD_START=$(date +"%s")
    echo -e "${blue}Making ${1} ${nocol}"
    make $1 \
	-j"${JOBS}" \
	O=$OUT_DIR \
	ARCH=$ARCH \
        CROSS_COMPILE=aarch64-linux-gnu- \
        CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
        LLVM=1 \
        LLVM_IAS=1

    BUILD_END=$(date +"%s")
    DIFF=$((${BUILD_END} - ${BUILD_START}))
    echo -e "${yellow}$1 Build completed in $(($DIFF / 60)) minute(s) and $(($DIFF % 60)) seconds.$nocol"
}

move_files() {
    echo -e "${blue}Movings Files${nocol}"
    xz -ck ${BUILTIMAGE} > ${ANYKERNEL_DIR}/Image.xz
    xz -ck ${BUILTDTB} > ${ANYKERNEL_DIR}/kernel_dtb.xz
}

make_zip() {
    cd ${ANYKERNEL_DIR}
    echo -e "${blue}Making Zip${nocol}"
    zip -r ${KERNELZIP} * > /dev/null
    cd -
}

enable_defconfig() {
    echo -e "${blue}Enabling ${1}${nocol}"
    ${KERNEL_DIR}/scripts/config --file ${OUT_DIR}/.config -e $1
}

disable_defconfig() {
    echo -e "${blue}Disabling ${1}${nocol}"
    ${KERNEL_DIR}/scripts/config --file ${OUT_DIR}/.config -d $1
}

generate_release_data() {
    cat <<EOF
{
"tag_name":"${BUILD_TIME}",
"target_commitish":"KCUF_419",
"name":"KCUFKernel-whyred-4.19-${BUILD_TIME}",
"body":"${KERNELZIP}",
"draft":false,
"prerelease":false,
"generate_release_notes":false
}
EOF
}

create_release() {
    url=https://api.github.com/repos/shekhawat2/android_kernel_xiaomi_whyred/releases
    upload_url=$(curl -s \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: token ${GITHUB_TOKEN}" \
        $url \
        -d "$(generate_release_data)" | jq -r .upload_url | cut -d { -f'1')
}

upload_release_file() {
    command="curl -s -o /dev/null -w '%{http_code}' \
        -H 'Authorization: token ${GITHUB_TOKEN}' \
        -H 'Content-Type: $(file -b --mime-type ${1})' \
        --data-binary @${1} \
        ${upload_url}?name=$(basename ${1})"

    http_code=$(eval $command)
    if [ $http_code == "201" ]; then
        echo "asset $(basename ${1}) uploaded"
    else
        echo "upload failed with code '$http_code'"
        exit 1
    fi
}

setup_env && clean_up
build vendor/whyred_defconfig
disable_defconfig CONFIG_NEWCAM_BLOBS
enable_defconfig CONFIG_DYNAMIC_WHYRED
if [ x$1 == xgz ]; then
    build
else
    build dtbs && build Image
fi
if [ ! -f ${BUILTIMAGE} ]; then
    echo "Image Build Failed" && exit 1
fi
if [ x$1 == xc ]; then
    move_files
    disable_defconfig CONFIG_DYNAMIC_WHYRED
    build dtbs
    $BSDIFF $BUILTDTB $BUILTFSTABDTB ${ANYKERNEL_DIR}/bspatch/dtb_fstab
    cp ${BUILTIMAGE} ${OUT_DIR}/Image
    enable_defconfig CONFIG_NEWCAM_BLOBS
    build Image
    $BSDIFF ${OUT_DIR}/Image ${BUILTIMAGE} ${ANYKERNEL_DIR}/bspatch/cam_newblobs
    make_zip
    create_release && echo "$upload_url"
    upload_release_file ${ANYKERNEL_DIR}/${KERNELZIP}
fi
