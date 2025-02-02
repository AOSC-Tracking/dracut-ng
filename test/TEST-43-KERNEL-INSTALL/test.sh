#!/usr/bin/env bash
# shellcheck disable=SC2034
TEST_DESCRIPTION="kernel-install with root filesystem on ext4 filesystem"

test_check() {
    if command -v systemd-detect-virt > /dev/null && ! systemd-detect-virt -c &> /dev/null; then
        echo "This test assumes that it runs inside a CI container."
        return 1
    fi

    if ! [ -e /usr/lib/modules/"$KVERSION"/vmlinuz ]; then
        echo "This test assumes that kernel-install can find the kernel at /usr/lib/modules/$KVERSION/vmlinuz"
        return 1
    fi

    if ! command -v kernel-install > /dev/null; then
        echo "This test needs kernel-install to run."
        return 1
    fi

    command -v systemctl &> /dev/null
}

test_run() {
    declare -a disk_args=()
    declare -i disk_index=0
    qemu_add_drive disk_index disk_args "$TESTDIR"/marker.img marker
    qemu_add_drive disk_index disk_args "$TESTDIR"/root.img root

    test_marker_reset

    "$testdir"/run-qemu \
        "${disk_args[@]}" \
        -append "$TEST_KERNEL_CMDLINE root=LABEL=dracut" \
        -initrd "$BOOT_ROOT/$TOKEN/$KVERSION"/initrd || return 1

    test_marker_check || return 1
}

test_setup() {
    # create root filesystem
    # shellcheck disable=SC2153
    "$DRACUT" -N --keep --tmpdir "$TESTDIR" \
        --add-confdir test-root \
        -f "$TESTDIR"/initramfs.root "$KVERSION" || return 1

    dd if=/dev/zero of="$TESTDIR"/root.img bs=200MiB count=1 status=none && sync
    mkfs.ext4 -q -L dracut -d "$TESTDIR"/dracut.*/initramfs/ "$TESTDIR"/root.img && sync

    mkdir -p /run/kernel
    echo 'initrd_generator=dracut' >> /run/kernel/install.conf

    # enable test dracut config
    cp /usr/lib/dracut/test/dracut.conf.d/test/test.conf /usr/lib/dracut/dracut.conf.d/

    # using kernell-install to invoke dracut
    mkdir -p "$BOOT_ROOT/$TOKEN/$KVERSION"
    kernel-install add-all
}

# shellcheck disable=SC1090
. "$testdir"/test-functions
