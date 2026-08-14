#pragma once

#include <sys/types.h>

int ports_on_mac_pid_cwd(pid_t pid, char *out, int out_size);
