
/* Functions to create and compare kstat snapshots */
#define _KSTAT_COMMON_H

#ifdef _cplusplus
extern "C" {
#endif


#include <stdio.h>
#include <kstat.h>
#include <sys/types.h>
#include <sys/sysinfo.h>
#include <sys/processor.h>
#include <sys/pset.h>


/* There is no CPU at this CPU location */
#define ID_NO_CPU -1
/* This CPU belongs to no pset (number as "pset 0")  */
#define ID_NO_PSET 0

/* Whether this CPU is usable */
#define CPU_ONLINE(s) ((s) == P_ONLINE || (s) == P_NOINTR)
/* Whether this CPU will have kstats */
#define CPU_ACTIVE(c) (CPU_ONLINE((c)->cs_state) && (c)->cs_id != ID_NO_CPU)

enum snapshot_types {
  /* All CPUs, independently */
  SNAP_CPUS                  =   1 << 0;
  /* Aggregated Processor Sets */
  SNAP_PSETS                 =   1 << 1;
  /* System Wide kstats, including aggregated CPU kstats */
  SNAP_SYSTEM                =   1 << 2;
  /* Interrupt sources and counts */
  SNAP_INTERRUPTS            =   1 << 3;
};

struct cpu_snapshot {
  /* If no CPU present, will be ID_NO_CPU */
  processorid_t cs_id;
  /* If no pset, will be ID_NO_PSET */
  psetid_t      cs_pset_id;
  /* the same state as used in p_online(2) */
  int           cs_state;
  /* Statistics for this particular CPU */
  kstat_t       cs_vm;
  kstat_t       cs_sys;
};

struct pset_snapshot {
  /* If ID is zero, it indicates the non existent set */
  psetid_t              ps_id;
  /* The number of CPUs in this set */
  size_t                ps_nr_cpus;
  /* The list of CPUs in this set */
  struct cpu_snapshot **ps_cpus;
};

struct intr_snapshot {
  /* Name of the interrupt source */
  char                  is_name[KSTAT_STRLEN];
  /* The total number of interrupts this source generated */
  ulong_t               is_total;
};

struct sys_snapshot {
  sysinfo_t             ss_sysinfo;
  vminfo_t              vm_sysinfo;
  struct ncstats        ss_nc;
  /* vm/sys states aggregated across all CPUs */
  kstat_t               ss_agg_vm;
  kstat_t               ss_agg_sys;
  /* ticks since boot */
  ulong_t               ss_ticks;
  long                  ss_deficit;
}

/* The primary structure of a system snapshot. */
struct snapshot {
  /* What types were **REQUESTED** */
  enum snapshot_types   s_types;
  size_t                s_nr_cpus;
  struct cpu_snapshot  *s_cpus;
  size_t                s_nr_psets;
  struct pset_snapshot *s_psets;
  size_t                s_nr_intrs;
  struct intr_snapshot *s_intrs;
  struct sys_snapshot   s_sys;
  size_t                s_nr_active_cpus;
}

/* print a message and exit with failure */
void fail(int do_perror, char *message, ...);

/* strdup str, or exit with failure */
char *safe_strdup(char *str);

/* malloc successfully, or exit with failure */
void *safe_alloc(size_t size);

/*
 * Copy a kstat from src to dst. If the source kstat contains no data,
 * then set the destination kstat data to NULL and size to zero.
 * Returns 0 on success.
 */
int kstat_copy(const kstat_t *src, kstat_t *dst);

/*
 * Look up the named kstat, and give the ui64 difference i.e.
 * new - old, or if old is NULL, return new.
 */
uint64_t kstat_delta(kstat_t *old, kstat_t *new, char *name);

/* Return the number of ticks delta between two hrtime_t values. */
uint64_t hrtime_delta(hrtime_t old, hrtime_t new);

/*
 * Add the integer-valued stats from "src" to the
 * existing ones in "dst". If "dst" does not contain
 * stats, then a kstat_copy() is performed.
 */
int kstat_add(const kstat_t *src, kstat_t *dst);

/* return the number of CPUs with kstats (i.e. present and online) */
int nr_active_cpus(struct snapshot *ss);

/*
 * Return the difference in CPU ticks between the two sys
 * kstats.
 */
uint64_t cpu_ticks_delta(kstat_t *old, kstat_t *new);

/*
 * Open the kstat chain. Cannot fail.
 */
kstat_ctl_t *open_kstat(void);

/*
 * Return a struct snapshot based on the snapshot_types parameter
 * passed in.
 */
struct snapshot *acquire_snapshot(kstat_ctl_t *, int);

/* free a snapshot */
void free_snapshot(struct snapshot *ss);

typedef void (*snapshot_cb)(void *old, void *new, void *data);

/*
 * Call the call back for each pair of data items of the given type,
 * passing the data pointer passed in as well. If an item has been
 * added, the first pointer will be NULL; if removed, the second pointer
 * will be NULL.
 *
 * A non-zero return value indicates configuration has changed.
 */
int snapshot_walk(enum snapshot_types type, struct snapshot *old,
    struct snapshot *new, snapshot_cb cb, void *data);

/*
 * Output a line detailing any configuration changes such as a CPU
 * brought online, etc, bracketed by << >>.
 */
void snapshot_report_changes(struct snapshot *old, struct snapshot *new);

/* Return non-zero if configuration has changed. */
int snapshot_has_changed(struct snapshot *old, struct snapshot *new);

/* sleep until *wakeup + interval, keeping cadence where desired */
void sleep_until(hrtime_t *wakeup, hrtime_t interval, int forever,
    int *caught_cont);

/* signal handler - so we can be aware of SIGCONT */
void cont_handler(int sig_number);

 

#ifdef _cplusplus
}
#endif

#endif  /* _KSTAT_COMMON_H */
