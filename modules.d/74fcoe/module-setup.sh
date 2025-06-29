#!/bin/bash

# called by dracut
check() {
    # shellcheck disable=SC2317  # called later by for_each_host_dev_and_slaves
    is_fcoe() {
        block_is_fcoe "$1" || return 1
    }

    [[ $hostonly_mode == "strict" ]] || [[ $mount_needs ]] && {
        for_each_host_dev_and_slaves is_fcoe || return 255
    }

    require_binaries dcbtool fipvlan lldpad ip readlink fcoemon fcoeadm tr || return 1
    return 0
}

# called by dracut
depends() {
    echo network rootfs-block initqueue
    return 0
}

# called by dracut
installkernel() {
    hostonly=$(optional_hostonly) instmods fcoe libfcoe 8021q edd bnx2fc
}

get_vlan_parent() {
    local link=$1

    [ -d "$link" ] || return
    read -r iflink < "$link"/iflink
    for if in /sys/class/net/*; do
        read -r idx < "$if"/ifindex
        if [ "$idx" -eq "$iflink" ]; then
            echo "${if##*/}"
        fi
    done
}

# called by dracut
cmdline() {
    {
        for c in /sys/bus/fcoe/devices/ctlr_*; do
            [ -L "$c" ] || continue
            read -r enabled < "$c"/enabled
            read -r mode < "$c"/mode
            [ "$enabled" -eq 0 ] && continue
            if [ "$mode" = "VN2VN" ]; then
                mode="vn2vn"
            else
                mode="fabric"
            fi
            d=$(
                cd -P "$c" || exit
                echo "$PWD"
            )
            i=${d%/*}
            ifname=${i##*/}
            read -r mac < "${i}"/address
            s=$(dcbtool gc "${i##*/}" dcb 2> /dev/null | sed -n 's/^DCB State:\t*\(.*\)/\1/p')
            if [ -z "$s" ]; then
                p=$(get_vlan_parent "${i}")
                if [ "$p" ]; then
                    s=$(dcbtool gc "${p}" dcb 2> /dev/null | sed -n 's/^DCB State:\t*\(.*\)/\1/p')
                    ifname=${p##*/}
                fi
            fi
            if [ "$s" = "on" ]; then
                dcb="dcb"
            else
                dcb="nodcb"
            fi

            # Some Combined Network Adapters(CNAs) implement DCB in firmware.
            # Do not run software-based DCB or LLDP on CNAs that implement DCB.
            # If the network interface provides hardware DCB/DCBX capabilities,
            # DCB_REQUIRED in "/etc/fcoe/cfg-xxx" is expected to set to "no".
            #
            # Force "nodcb" if there's any DCB_REQUIRED="no"(child or vlan parent).
            if grep -q '^[[:blank:]]*DCB_REQUIRED="no"' /etc/fcoe/cfg-"${i##*/}" &> /dev/null; then
                dcb="nodcb"
            fi

            if [ "$p" ]; then
                if grep -q '^[[:blank:]]*DCB_REQUIRED="no"' /etc/fcoe/cfg-"${p}" &> /dev/null; then
                    dcb="nodcb"
                fi
            fi

            echo "ifname=${ifname}:${mac}"
            echo "fcoe=${ifname}:${dcb}:${mode}"
        done
    } | sort | uniq
}

# called by dracut
install() {
    inst_multiple ip dcbtool fipvlan lldpad readlink lldptool fcoemon fcoeadm tr
    if [[ -e "${dracutsysrootdir-}/etc/hba.conf" ]]; then
        inst_libdir_file 'libhbalinux.so*'
        inst_simple "/etc/hba.conf"
    fi

    mkdir -m 0755 -p "$initdir/var/lib/lldpad"
    mkdir -m 0755 -p "$initdir/etc/fcoe"

    if [[ $hostonly_cmdline == "yes" ]]; then
        local _fcoeconf
        _fcoeconf=$(cmdline)
        [[ $_fcoeconf ]] && printf "%s\n" "$_fcoeconf" >> "${initdir}/etc/cmdline.d/95fcoe.conf"
    fi
    inst_multiple "/etc/fcoe/cfg-*"

    inst "$moddir/fcoe-up.sh" "/sbin/fcoe-up"
    inst "$moddir/fcoe-edd.sh" "/sbin/fcoe-edd"
    inst_hook pre-trigger 03 "$moddir/lldpad.sh"
    inst_hook cmdline 99 "$moddir/parse-fcoe.sh"
    inst_hook cleanup 90 "$moddir/cleanup-fcoe.sh"
    inst_hook shutdown 40 "$moddir/stop-fcoe.sh"
}
