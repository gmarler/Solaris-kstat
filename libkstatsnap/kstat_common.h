
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


#ifdef _cplusplus
}
#endif

#endif  /* _KSTAT_COMMON_H */
