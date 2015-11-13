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

static int
acquire_psets(struct snapshot *ss)
{
  psetid_t             *pids = NULL;
  struct pset_snapshot *ps;
  size_t                pids_nr;
  size_t                i, j;

  /*
   * WARNING: Have to use pset_list twice, but between the two calls
   *          pids_nr can change at will.
   *          Delay the setting of s_nr_psets until we have the "final"
   *          of pids_nr
   */

  if (pset_list(NULL, &pids_nr) < 0)
    return (errno);

  if ((pids = calloc(pids_nr, sizeof (psetid_t))) == NULL)
    goto out;

  if (pset_list(pids, &pids_nr) < 0)
    goto out;

  ss->s_psets = calloc(pids_nr + 1, sizeof (struct pset_snapshot));
  if (ss->s_psets == NULL)
    goto out;
  ss->s_nr_psets = pids_nr + 1;

  /* CPUs that are not in any pset */
  ps = &ss->s_psets[0];
  ps->ps_id = 0;
  ps->ps_cpus = calloc(ss->s_nr_cpus, sizeof (struct cpu_snapshot *));
  if (ps->ps_cpus == NULL)
    goto out;

  /* CPUs that are in a pset */
  for (i = 1; i < ss->s_nr_psets; i++) {
    ps = &ss->s_psets[i];

    ps->ps_id = pids[i - 1];
    ps->ps_cpus =
      calloc(ss->s_nr_cpus, sizeof (struct cpu_snapshot *));
    if (ps->ps_cpus == NULL)
      goto out;
  }

  for (i = 0; i < ss->s_nr_psets; i++) {
    ps = &ss->s_psets[i];

    for (j = 0; j < ss->s_nr_cpus; j++) {
      if (!CPU_ACTIVE(&ss->s_cpus[j]))
        continue;
      if (ss->s_cpus[j].cs_pset_id != ps->ps_id)
        continue;

      ps->ps_cpus[ps->ps_nr_cpus++] = &ss->s_cpus[j];
    }
  }

  errno = 0;

out:
  free(pids);
  return (errno);
}

