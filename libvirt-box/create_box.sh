#!/usr/bin/env bash
#set -xu

error() {
    local msg="${1}"
    echo "==> ERROR: ${msg}"
    exit 1
}

usage() {
    echo "Usage: ${0} IMAGE [BOX]"
    echo
    echo "Package a qcow2 image into a vagrant-libvirt reusable box"
}

# Print the image's backing file
backing(){
    local img=${1}
    qemu-img info "$img" | grep 'backing file:' | cut -d ':' -f2
}

# Rebase the image
rebase(){
    local img=${1}
    qemu-img rebase -p -b "" "$img"
    [[ "$?" -ne 0 ]] && error "Error during rebase"
}

# Shrink the image
shrink(){
    local img=${1}
    mv $img ${img}_backup
    qemu-img convert -O qcow2 ${img}_backup $img
    [[ "$?" -ne 0 ]] && error "Error during shrinking"
}

# Is absolute path
isabspath(){
    local path=${1}
    [[ "$path" =~ ^/.* ]]
}

if [ -z "$1" ]; then
    usage
    exit 1
fi

IMG=$(readlink -e "$1")
[[ "$?" -ne 0 ]] && error "'$1': No such image"

IMG_DIR=$(dirname "$IMG")
IMG_BASENAME=$(basename "$IMG")
echo "==> using image: $IMG"
echo "==> using image dir: $IMG_DIR"
echo "==> using image name: $IMG_BASENAME"

BOX=${2:-}
# If no box name is supplied infer one from image name
if [[ -z "$BOX" ]]; then
    BOX_NAME=${IMG_BASENAME%.*}
    BOX=$BOX_NAME.box
else
    BOX_NAME=$(basename "${BOX%.*}")
fi

echo "==> using box name: $BOX_NAME"
echo "==> using box: $BOX"

[[ -f "$BOX" ]] && error "'$BOX': Already exists"

CWD=$(pwd)
TMP_DIR="$CWD/_tmp_package"
TMP_IMG="$TMP_DIR/box.img"

mkdir -p "$TMP_DIR"

[[ ! -r "$IMG" ]] && error "'$IMG': Permission denied"

# We move / copy (when the image has master) the image to the tempdir
# ensure that it's moved back / removed again
if [[ -n $(backing "$IMG") ]]; then
    echo "==> Image has backing image, copying image and rebasing ..."
    # trap "rm -rf $TMP_DIR" EXIT
    cp "$IMG" "$TMP_IMG"
    rebase "$TMP_IMG"
else
    if fuser -s "$IMG"; then
        error "Image '$IMG_BASENAME' is used by another process"
    fi

    # move the image to get a speed-up and use less space on disk
    trap 'mv "$TMP_IMG" "$IMG"' EXIT
    #trap 'mv "$TMP_IMG" "$IMG"; rm -rf "$TMP_DIR"' EXIT

    mv "$IMG" "$TMP_IMG"
fi

echo "==> recompressing image"
shrink "$TMP_IMG"

cd "$TMP_DIR"

IMG_SIZE=$(qemu-img info "$TMP_IMG" | grep 'virtual size' | awk '{print $3;}' | tr -d 'G' | cut -d '.' -f1)
echo "==> image size: $IMG_SIZE"

# use default unless .base exists
if [ ! -f $CWD/metadata.json.base ]; then
  echo "==> using default metadata config"

  cat > metadata.json <<EOF
{
    "provider": "libvirt",
    "format": "qcow2",
    "virtual_size": ${IMG_SIZE}
}
EOF
else
  echo "==> using metadata from base file"
  sed "s/IMGSIZE/"$IMG_SIZE"/g" $CWD/metadata.json.base > metadata.json
fi

# use default unless .base exists
if [ ! -f $CWD/Vagrantfile.base ]; then
  echo "==> using default Vagrantfile"
  cat > Vagrantfile <<EOF
Vagrant.configure("2") do |config|

  config.vm.provider :libvirt do |libvirt|

    libvirt.driver = "kvm"
    libvirt.host = ""
    libvirt.connect_via_ssh = false
    libvirt.storage_pool_name = "default"

  end
end
EOF
else
  # else just use the .base file
  echo "==> using Vagrantfile from base"
  cp $CWD/Vagrantfile.base Vagrantfile
fi



echo "==> Creating box, tarring and gzipping"

tar cvzf "$BOX" --totals ./metadata.json ./Vagrantfile ./box.img

# if box is in tmpdir move it to CWD before removing tmpdir
if ! isabspath "$BOX"; then
    mv "$BOX" "$CWD"
fi

echo "==> ${BOX} created"
echo "==> You can now add the box:"
echo "==>   'vagrant box add ${BOX} --name ${BOX_NAME}'"
