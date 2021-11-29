#!/bin/bash
blue='\033[0;34m'
cyan='\033[0;36m'
yellow='\033[0;33m'
red='\033[0;31m'
nocol='\033[0m'

if [[ $1 == clean || $1 == c ]]; then
    echo "Building Clean"
    type=clean
elif [[ $1 == dirty || $1 == d ]]; then
    echo "Building Dirty"
    type=dirty
else
    echo "Please specify type: clean or dirty"
    exit
fi

setup_env() {
if [ ! -d $CLANG_DIR ]; then
    echo "clang directory does not exists, cloning now..."
    git clone git@github.com:kdrag0n/proton-clang ../pclang --depth 1
fi
if [ ! -d $ANYKERNEL_DIR ]; then
    echo "anykernel directory does not exists, cloning now..."
    git clone git@github.com:shekhawat2/AnyKernel3 -b whyredo ../anykernel
fi
if [ ! -d $KERNELBUILDS_DIR ]; then
    echo "builds directory does not exists, creating now..."
    mkdir -p $KERNELBUILDS_DIR
fi
export PATH=${CLANG_DIR}/bin:${KERNEL_DIR}/bin:${PATH}
export KBUILD_COMPILER_STRING=$(${CLANG_DIR}/bin/clang --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')
}

export_vars() {
export KERNEL_DIR=${PWD}
export KBUILD_BUILD_USER="Shekhawat2"
export KBUILD_BUILD_HOST="Builder"
export ARCH=arm64
export CLANG_DIR=${KERNEL_DIR}/../pclang
export OUT_DIR=${KERNEL_DIR}/out
export ANYKERNEL_DIR=${KERNEL_DIR}/../anykernel
export KERNELBUILDS_DIR=${KERNEL_DIR}/../kernelbuilds
export JOBS="$(grep -c '^processor' /proc/cpuinfo)"
export BSDIFF=${KERNEL_DIR}/bin/bsdiff
export BUILD_TIME=$(date +"%Y%m%d-%T")
export KERNELZIP=${ANYKERNEL_DIR}/KCUFKernel-whyred-EAS-${BUILD_TIME}.zip
export BUILTIMAGE=${OUT_DIR}/arch/arm64/boot/Image
export BUILTDTB=${OUT_DIR}/arch/arm64/boot/dts/qcom/whyred.dtb
export BUILTDTBQTI=${OUT_DIR}/arch/arm64/boot/dts/qcom/whyred_qtihap.dtb
}

clean_up() {
echo -e "${cyan}Cleaning Up ${nocol}"
rm -rf $OUT_DIR
rm -rf ${ANYKERNEL_DIR}/Image* ${ANYKERNEL_DIR}/kernel_dtb*
rm -rf ${ANYKERNEL_DIR}/*.xz ${ANYKERNEL_DIR}/*.zip ${ANYKERNEL_DIR}/bspatch/*
make clean && make mrproper
}

build() {
BUILD_START=$(date +"%s")
echo -e "${blue}Making ${1} ${nocol}"
make $1 \
	-j"${JOBS}" \
	O=$OUT_DIR \
	ARCH=$ARCH \
	CC="ccache clang" \
	CROSS_COMPILE=aarch64-linux-gnu- \
	CROSS_COMPILE_ARM32=arm-linux-gnueabi-
BUILD_END=$(date +"%s")
DIFF=$((${BUILD_END} - ${BUILD_START}))
echo -e "${yellow}$1 Build completed in $(($DIFF / 60)) minute(s) and $(($DIFF % 60)) seconds.$nocol"
}

move_files() {
echo -e "${blue}Movings Files${nocol}"
xz -c ${OUT_DIR}/Image > ${ANYKERNEL_DIR}/Image.xz
xz -c ${BUILTDTB} > ${ANYKERNEL_DIR}/kernel_dtb.xz
xz -c ${BUILTDTBQTI} > ${ANYKERNEL_DIR}/kernel_dtbqti.xz
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

export_vars
setup_env
if [ $type == clean ]; then
clean_up
fi
build whyred_defconfig
disable_defconfig CONFIG_INPUT_QTI_HAPTICS #one
build dtbs
enable_defconfig CONFIG_INPUT_QTI_HAPTICS #keepit
build dtbs
disable_defconfig CONFIG_XIAOMI_NEW_CAMERA_BLOBS #safe
build Image
if [ $type == dirty ]; then
echo "Dirty Build Complete"
exit 0
fi
if [ -f ${BUILTIMAGE} ]; then
mv ${BUILTIMAGE} ${OUT_DIR}/Image
else
echo "Image Build Failed"
exit 1
fi
enable_defconfig CONFIG_XIAOMI_NEW_CAMERA_BLOBS #fine
build Image
if [ ! -f ${BUILTIMAGE} ]; then
echo "Image Build Failed"
exit 1
fi
${KERNEL_DIR}/bin/bsdiff ${OUT_DIR}/Image ${BUILTIMAGE} ${ANYKERNEL_DIR}/bspatch/newcam.patch
if [ $type == clean ]; then
move_files
make_zip
upload_gdrive
fi
