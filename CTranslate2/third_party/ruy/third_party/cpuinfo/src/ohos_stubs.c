#include <cpuinfo/internal-api.h>

void cpuinfo_x86_linux_init(void)
{
  cpuinfo_is_initialized = true;
}

void cpuinfo_arm_linux_init(void)
{
  cpuinfo_is_initialized = true;
}
