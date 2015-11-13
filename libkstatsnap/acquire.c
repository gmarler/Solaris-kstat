#include "kstat_common.h"

#include <stdlib.h>
#include <unistd.h>
#include <strings.h>
#include <errno.h>
#include <limits.h>
#include <time.h>

#define ARRAY_SIZE(a) (sizeof (a) / sizeof (*a))

/*
 * How long we delay before retrying after an allocation failure,
 * in units of milleseconds
 */
#define RETRY_DELAY 200

static char *cpu_states[] = {
  "cpu_ticks_idle",
  "cpu_ticks_user",
  "cpu_ticks_kernel",
  "cpu_ticks_wait"
};



static kstat_t *
kstat_lookup_read(kstat_ctl_t *kc, char *module, int instance, char *name)
{
  kstat_t *ksp = kstat_lookup(kc, module, instance, name);
  if (ksp == NULL)
    return (NULL);
  if (kstat_read(kc, ksp, NULL) == -1)
    return (NULL);
  return (ksp);
}

/*
 * NOTE: The following helper routines do not clean up in the case of failure.
 *       That is left to the free_snapshot() routine in the acquire_snapshot()
 *       failure path.
 */

static int
acquire_cpus(struct snapshot *ss, kstat_ctl_t *kc)
{
  size_t i;

  ss->s_nr_cpus = sysconf(_SC_CPUID_MAX) + 1;
  ss->s_cpus = calloc(ss->s_nr_cpus, sizeof (struct cpu_snapshot));
  if (ss->s_cpus == NULL)
    goto out;

  for (i = 0; i < ss->s_nr_cpus; i++) {
    kstat_t *ksp;

    ss->s_cpus[i].cs_id    = ID_NO_CPU;
    ss->s_cpus[i].cs_state = p_online(i, P_STATUS);

    /* If no valid CPU is present, move on to the next CPU */
    if (ss->s_cpus[i].cs_state == -1)
      continue;
    ss->s_cpus[i].cs_id = i;

    if ((ksp = kstat_lookup_read(kc, "cpu_info", i, NULL)) == NULL)
      goto out;

    (void)pset_assign(PS_QUERY, i, &ss->s_cpus[i].cs_pset_id);
    if (ss->s_cpus[i].cs_pset_id == PS_NONE)
      ss->s_cpus[i].cs_pset_id = ID_NO_PSET;

    if (!CPU_ACTIVE(&ss->s_cpus[i]))
      continue;

    if ((ksp = kstat_lookup_read(kc, "cpu", i, "vm")) == NULL)
      goto out;

    if (kstat_copy(ksp, &ss->s_cpus[i].cs_vm))
      goto out;

    if ((ksp = kstat_lookup_read(kc, "cpu", i, "sys")) == NULL)
      goto out;

    if (kstat_copy(ksp, &ss->s_cpus[i].cs_sys))
      goto out;
  }

  errno = 0;

out:
  return (errno);
}
