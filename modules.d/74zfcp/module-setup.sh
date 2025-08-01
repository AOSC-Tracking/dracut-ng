#!/bin/bash

# called by dracut
check() {
    arch=${DRACUT_ARCH:-$(uname -m)}
    [ "$arch" = "s390" ] || [ "$arch" = "s390x" ] || return 1

    require_binaries zfcp_cio_free sed || return 1

    return 0
}

# called by dracut
installkernel() {
    instmods zfcp
}

# called by dracut
install() {
    inst_hook cmdline 30 "$moddir/parse-zfcp.sh"
    inst_multiple zfcp_cio_free sed

    inst_script /sbin/zfcpconf.sh
    inst_rules 56-zfcp.rules

    if [[ ${hostonly-} ]]; then
        inst_simple -H /etc/zfcp.conf
    fi
}
