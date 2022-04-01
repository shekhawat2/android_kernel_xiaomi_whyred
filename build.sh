#!/bin/bash
set -e
blue='\033[0;34m'
cyan='\033[0;36m'
yellow='\033[0;33m'
red='\033[0;31m'
nocol='\033[0m'

setup_env() {
    if [ ! -d $CLANG_DIR ]; then
        echo "clang directory does not exists, cloning now..."
        git clone git@gitlab.com:Shekhawat2/clang-builds ${CLANG_DIR} --depth 1
    fi
    if [ ! -d $ANYKERNEL_DIR ]; then
        echo "anykernel directory does not exists, cloning now..."
        git clone git@github.com:shekhawat2/AnyKernel3 -b whyred_419 ../anykernel
    fi
    export PATH=${CLANG_DIR}/bin:${KERNEL_DIR}/bin:${PATH}
    export KBUILD_COMPILER_STRING=$(${CLANG_DIR}/bin/clang --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')
}

export_vars() {
    export KERNEL_DIR=${PWD}
    export KBUILD_BUILD_USER="Shekhawat2"
    export KBUILD_BUILD_HOST="Builder"
    export ARCH=arm64
    export CLANG_DIR=${KERNEL_DIR}/../clang-builds
    export OUT_DIR=${KERNEL_DIR}/out
    export ANYKERNEL_DIR=${KERNEL_DIR}/../anykernel
    export JOBS="$(grep -c '^processor' /proc/cpuinfo)"
    export BSDIFF=${KERNEL_DIR}/bin/bsdiff
    export BUILD_TIME=$(date +"%Y%m%d-%T")
    export KERNELZIP=${ANYKERNEL_DIR}/KCUFKernel-whyred-4.19-${BUILD_TIME}.zip
    export BUILTIMAGE=${OUT_DIR}/arch/arm64/boot/Image
    export BUILTDTB=${OUT_DIR}/arch/arm64/boot/dts/vendor/qcom/whyred.dtb
    export BUILTFSTABDTB=${OUT_DIR}/arch/arm64/boot/dts/vendor/qcom/whyred_fstab.dtb
    export BSDIFF=${KERNEL_DIR}/bin/bsdiff
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
    BUILD_TIME=$(date +"%Y%m%d-%T")
    zip -r ${KERNELZIP} * > /dev/null
    cd -
}

upload_gdrive() {
    gdrive upload --share ${KERNELZIP}
}

enable_defconfig() {
    echo -e "${blue}Enabling ${1}${nocol}"
    ${KERNEL_DIR}/scripts/config --file ${OUT_DIR}/.config -e $1
}

disable_defconfig() {
    echo -e "${blue}Disabling ${1}${nocol}"
    ${KERNEL_DIR}/scripts/config --file ${OUT_DIR}/.config -d $1
}

export_vars && setup_env
clean_up
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
    upload_gdrive
fi
