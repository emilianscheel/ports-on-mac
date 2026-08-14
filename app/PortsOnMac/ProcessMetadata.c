#include "ProcessMetadata.h"

#include <libproc.h>
#include <string.h>

int ports_on_mac_pid_cwd(pid_t pid, char *out, int out_size) {
    struct proc_vnodepathinfo vpi;
    int ret = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vpi, (int)sizeof(vpi));
    if (ret <= 0 || out == NULL || out_size <= 1) {
        return -1;
    }

    strncpy(out, vpi.pvi_cdir.vip_path, (size_t)out_size - 1);
    out[out_size - 1] = '\0';
    return out[0] == '\0' ? -1 : 0;
}
