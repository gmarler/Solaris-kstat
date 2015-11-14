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

static int
acquire_intrs(struct snapshot *ss, kstat_ctl_t *kc)
{
  kstat_t       *ksp;
  size_t         i = 0;
  kstat_t       *sys_misc;
  kstat_named_t *clock;

  /* clock interrupt */
  ss->s_nr_intrs = 1;

  for (ksp = kc->kc_chain; ksp; ksp = ksp->ks_next){
    if (ksp->ks_type == KSTAT_TYPE_INTR)
      ss->s_nr_intrs++;
  }

  ss->intrs = calloc(s->s_nr_intrs, sizeof (struct intr_snapshot));
  if (ss->s_intrs == NULL)
    return (errno);

  sys_misc = kstat_lookup_read(kc, "unix", 0, "system_misc");
  if (sys_misc == NULL)
    goto out;

  clock = (kstat_named_t *)kstat_data_lookup(sys_misc, "clk_intr");
  if (clock == NULL)
    goto out;

  (void) strlcpy(ss->s_intrs[0].is_name, "clock", KSTAT_STRLEN);
  ss->s_intrs[0].is_total = clock->value.ui32;

  i = 1;

  for (ksp = kc->kc_chain; ksp; ksp = ksp->ks_next) {
    kstat_intr_t *ki;
    int           j;

    if (ksp->ks_type != KSTAT_TYPE_INTR)
      continue;
    if (kstat_read(kc, ksp, NULL) == -1)
      goto out;

    ki = KSTAT_INTR_PTR(ksp);

    (void) strlcpy(ss->s_intrs[i].is_name, ksp->ks_name, KSTAT_STRLEN);
    ss->s_intrs[i].is_total = 0;

    for (j = 0; j < KSTAT_NUM_INTRS; j++)
      ss->s_intrs[i].is_total += ki->intrs[j];

    i++;
  }

  errno = 0;
out:
  return (errno);
}


int
acquire_sys(struct snapshot *ss, kstat_ctl_t *kc)
{
  size_t         i;
  kstat_named_t *knp;
  kstat_t       *ksp;

  if ((ksp = kstat_lookup(kc, "unix", 0, "sysinfo")) == NULL)
    return (errno);

  if (kstat_read(kc, ksp, &ss->s_sys.ss_sysinfo) == -1)
    return (errno);

  if ((ksp = kstat_lookup(kc, "unix", 0, "vminfo")) == NULL)
    return (errno);

  if (kstat_read(kc, ksp, &ss->s_sys.ss_vminfo) == -1)
    return (errno);

  if ((ksp = kstat_lookup(kc, "unix", 0, "dnlcstats")) == NULL)
    return (errno);

  if (kstat_read(kc, ksp, &ss->s_sys.ss_nc) == -1)
    return (errno);

  if (ksp = kstat_lookup(kc, "unix", 0, "system_misc")) == NULL)
    return (errno);

  if (kstat_read(kc, ksp, NULL) == -1)
    return (errno);

  knp = (kstat_named_t *)kstat_data_lookup(ksp, "clk_intr");
  if (knp == NULL)
    return (errno);

  ss->s_sys.ss_ticks = knp->value.l;

  knp = (kstat_named_t *)kstat_data_lookup(ksp, "deficit");
  if (knp == NULL)
    return (errno);
 
  ss->s_sys.ss_deficit = knp->value.l;

  for (i = 0; i < ss->s_nr_cpus; i++) {
    if (!CPU_ACTIVE(&ss->s_cpus[i]))
      continue;

    if (kstat_add(&ss->s_cpus[i].cs_sys, &ss->s_sys.ss_agg_sys))
      return (errno);
    if (kstat_add(&ss->s_cpus[i].cs_vm,  &ss->s_sys.ss_agg_vm))
      return (errno);
    ss->s_nr_active_cpus++;
  }

  return (0);
}

struct snapshot *
acquire_snapshot(kstat_ctl_t *kc, int types)
{
  struct snapshot *ss = NULL;
  int              err;

retry:
  err = 0;
  /* Make sure any partial resources are freed on a retry */
  free_snapshot(ss);

  ss = safe_alloc(sizeof (struct snapshot));

  (void) memset(ss, 0, sizeof (struct snapshot));

  ss->s_types = types;

  /* Wait for a possibly up to date chain */
  while (kstat_chain_update(kc) == -1) {
    if (errno == EAGAIN)
      /* TODO: replace with nanosleep */
      (void) poll(NULL, 0, RETRY_DELAY);
    else
      fail(1, "kstat_chain_update failed");
  }

  if (!err && (types & SNAP_INTERRUPTS))
    err = acquire_intrs(ss, kc);

  if (!err && (types & (SNAP_CPUS | SNAP_SYSTEM | SNAP_PSETS)))
    err = acquire_cpus(ss, kc);

  if (!err && (types & SNAP_PSETS))
    err = acquire_psets(ss);

  if (!err && (types & SNAP_SYSTEM))
    err = acquire_sys(ss, kc);

  switch (err) {
    case 0:
      break;
    case EAGAIN:
      /* TODO: Replace with nanosleep */
      (void) poll(NULL, 0, RETRY_DELAY);
    /* A kstat disappeared out from under us */
    /* FALLTHROUGH */
    case ENXIO:
    case ENOENT:
      goto retry;
    default:
      fail(1, "acquiring snapshot failed");
  }

  return (ss);
}

void
free_snapshot(struct snapshot *ss)
{
  size_t i;

  if (ss == NULL)
    return;

  while (ss->s_cpus) {
    for (i = 0; i < ss->s_nr_cpus; i++) {
      free(ss->s_cpus[i].cs_vm.ks_data);
      free(ss->s_cpus[i].cs_sys.ks_data);
    }
    free(ss->s_cpus);
  }

  if (ss->s_psets) {
    for (i = 0; i < ss->s_nr_psets; i++)
      free(ss->s_psets[i].ps_cpus);
    free(ss->s_psets);
  }

  free(ss->s_sys.ss_agg_sys.ks_data);
  free(ss->s_sys.ss_agg_vm.ks_data);
  free(ss);
}


