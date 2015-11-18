/* See perlguts for explanation of this */
/* #define PERL_NO_GET_CONTEXT */

/* Perl XS includes */
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

/* kstat related includes */
#include <kstat.h>
#include <libgen.h>
#include <sys/var.h>
#include <sys/utsname.h>
#include <sys/sysinfo.h>
#include <sys/flock.h>

/* for gethrtime() */
#include <sys/time.h>

/* Debug macros */
#define DEBUG_ID "Solaris::kstat"

#ifdef KSTAT_DEBUG
#  define PERL_ASSERT(EXP) \
      ((void)((EXP) || (croak("%s: assertion failed at %s:%d: %s", \
                        DEBUG_ID, __FILE__, __LINE__, #EXP), 0), 0))
#  define PERL_ASSERTMSG(EXP, MSG) \
      ((void)((EXP) || (croak(DEBUG_ID ": " MSG), 0), 0))
#else
#  define PERL_ASSERT(EXP)    ((void)0)
#  define PERL_ASSERTMSG(EXP, MSG)  ((void)0)
#endif


/* Macros for saving the contents of KSTAT_RAW structures */
#if defined(HAS_QUAD) && defined(USE_64_BIT_INT)
#  define NEW_IV(V) \
          (newSViv((IVTYPE) V))
#  define NEW_UV(V) \
          (newSVuv((UVTYPE) V))
#else
#  define NEW_IV(V) \
     (V >= IV_MIN && V <= IV_MAX ? newSViv((IVTYPE) V) : newSVnv((NVTYPE) V))
#  if defined(UVTYPE)
#    define NEW_UV(V) \
       (V <= UV_MAX ? newSVuv((UVTYPE) V) : newSVnv((NVTYPE) V))
#  else
#  define NEW_UV(V) \
       (V <= IV_MAX ? newSViv((IVTYPE) V) : newSVnv((NVTYPE) V))
#  endif
#endif

#define NEW_HRTIME(V) \
   NEW_UV(V)
/*     newSVnv((NVTYPE) (V / 1000000000.0))
 * 
 */

#define SAVE_FNP(H, F, K) \
    hv_store(H, K, sizeof (K) - 1, newSViv((IVTYPE)(uintptr_t)&F), 0)
#define SAVE_STRING(H, S, K, SS) \
    hv_store(H, #K, sizeof (#K) - 1, \
    newSVpvn(S->K, SS ? strlen(S->K) : sizeof(S->K)), 0)
#define SAVE_INT32(H, S, K) \
    hv_store(H, #K, sizeof (#K) - 1, NEW_IV(S->K), 0)
#define SAVE_UINT32(H, S, K) \
    hv_store(H, #K, sizeof (#K) - 1, NEW_UV(S->K), 0)
#define SAVE_INT64(H, S, K) \
    hv_store(H, #K, sizeof (#K) - 1, NEW_IV(S->K), 0)
#define SAVE_UINT64(H, S, K) \
    hv_store(H, #K, sizeof (#K) - 1, NEW_UV(S->K), 0)
#define SAVE_HRTIME(H, S, K) \
    hv_store(H, #K, sizeof (#K) - 1, NEW_HRTIME(S->K), 0)


/* Private structure used for saving kstat info in the tied hashes */
typedef struct {
  char         read;      /* Kstat block has been read before */
  char         valid;     /* Kstat still exists in kstat chain */
  char         strip_str; /* Strip KSTAT_DATA_CHAR fields */
  kstat_ctl_t *kstat_ctl; /* Handle returned by kstat_open */
  kstat_t     *kstat;     /* Handle used by kstat_read */
} KstatInfo_t;

/* typedef for apply_to_ties callback functions */
typedef int (*ATTCb_t)(HV *, void *);

/* typedef for raw kstat reader functions */
typedef void (*kstat_raw_reader_t)(HV *, kstat_t *, int);

/* Hash of "module:name" to KSTAT_RAW read functions */
static HV *raw_kstat_lookup;

/* C functions */

/*
 * Kstats come in two flavours, named and raw.  Raw kstats are just C structs,
 * so we need a function per raw kstat to convert the C struct into the
 * corresponding perl hash.  All such conversion functions are in the following
 * section.
 */

/*
 * Definitions in /usr/include/sys/cpuvar.h and /usr/include/sys/sysinfo.h
 */

  static void
save_cpu_stat(HV *self, kstat_t *kp, int strip_str)
{
  cpu_stat_t    *statp;
  cpu_sysinfo_t *sysinfop;
  cpu_syswait_t *syswaitp;
  cpu_vminfo_t  *vminfop;

  /* PERL_ASSERT(kp->ks_ndata == 1); */
  PERL_ASSERT(kp->ks_data_size == sizeof (cpu_stat_t));
  statp = (cpu_stat_t *)(kp->ks_data);
  sysinfop = &statp->cpu_sysinfo;
  syswaitp = &statp->cpu_syswait;
  vminfop  = &statp->cpu_vminfo;

  hv_store(self, "idle", 4, NEW_UV(sysinfop->cpu[CPU_IDLE]), 0);
  hv_store(self, "user", 4, NEW_UV(sysinfop->cpu[CPU_USER]), 0);
  hv_store(self, "kernel", 6, NEW_UV(sysinfop->cpu[CPU_KERNEL]), 0);
  hv_store(self, "wait", 4, NEW_UV(sysinfop->cpu[CPU_WAIT]), 0);
  hv_store(self, "wait_io", 7, NEW_UV(sysinfop->wait[W_IO]), 0);
  hv_store(self, "wait_swap", 9, NEW_UV(sysinfop->wait[W_SWAP]), 0);
  hv_store(self, "wait_pio",  8, NEW_UV(sysinfop->wait[W_PIO]), 0);
  SAVE_UINT32(self, sysinfop, bread);
  SAVE_UINT32(self, sysinfop, bwrite);
  SAVE_UINT32(self, sysinfop, lread);
  SAVE_UINT32(self, sysinfop, lwrite);
  SAVE_UINT32(self, sysinfop, phread);
  SAVE_UINT32(self, sysinfop, phwrite);
  SAVE_UINT32(self, sysinfop, pswitch);
  SAVE_UINT32(self, sysinfop, trap);
  SAVE_UINT32(self, sysinfop, intr);
  SAVE_UINT32(self, sysinfop, syscall);
  SAVE_UINT32(self, sysinfop, sysread);
  SAVE_UINT32(self, sysinfop, syswrite);
  SAVE_UINT32(self, sysinfop, sysfork);
  SAVE_UINT32(self, sysinfop, sysvfork);
  SAVE_UINT32(self, sysinfop, sysexec);
  SAVE_UINT32(self, sysinfop, readch);
  SAVE_UINT32(self, sysinfop, writech);
  SAVE_UINT32(self, sysinfop, rcvint);
  SAVE_UINT32(self, sysinfop, xmtint);
  SAVE_UINT32(self, sysinfop, mdmint);
  SAVE_UINT32(self, sysinfop, rawch);
  SAVE_UINT32(self, sysinfop, canch);
  SAVE_UINT32(self, sysinfop, outch);
  SAVE_UINT32(self, sysinfop, msg);
  SAVE_UINT32(self, sysinfop, sema);
  SAVE_UINT32(self, sysinfop, namei);
  SAVE_UINT32(self, sysinfop, ufsiget);
  SAVE_UINT32(self, sysinfop, ufsdirblk);
  SAVE_UINT32(self, sysinfop, ufsipage);
  SAVE_UINT32(self, sysinfop, ufsinopage);
  SAVE_UINT32(self, sysinfop, inodeovf);
  SAVE_UINT32(self, sysinfop, fileovf);
  SAVE_UINT32(self, sysinfop, procovf);
  SAVE_UINT32(self, sysinfop, intrthread);
  SAVE_UINT32(self, sysinfop, intrblk);
  SAVE_UINT32(self, sysinfop, idlethread);
  SAVE_UINT32(self, sysinfop, inv_swtch);
  SAVE_UINT32(self, sysinfop, nthreads);
  SAVE_UINT32(self, sysinfop, cpumigrate);
  SAVE_UINT32(self, sysinfop, xcalls);
  SAVE_UINT32(self, sysinfop, mutex_adenters);
  SAVE_UINT32(self, sysinfop, rw_rdfails);
  SAVE_UINT32(self, sysinfop, rw_wrfails);
  SAVE_UINT32(self, sysinfop, modload);
  SAVE_UINT32(self, sysinfop, modunload);
  SAVE_UINT32(self, sysinfop, bawrite);
#ifdef STATISTICS	/* see header file */
  SAVE_UINT32(self, sysinfop, rw_enters);
  SAVE_UINT32(self, sysinfop, win_uo_cnt);
  SAVE_UINT32(self, sysinfop, win_uu_cnt);
  SAVE_UINT32(self, sysinfop, win_so_cnt);
  SAVE_UINT32(self, sysinfop, win_su_cnt);
  SAVE_UINT32(self, sysinfop, win_suo_cnt);
#endif

  SAVE_INT32(self, syswaitp, iowait);
  SAVE_INT32(self, syswaitp, swap);
  SAVE_INT32(self, syswaitp, physio);

  SAVE_UINT32(self, vminfop, pgrec);
  SAVE_UINT32(self, vminfop, pgfrec);
  SAVE_UINT32(self, vminfop, pgin);
  SAVE_UINT32(self, vminfop, pgpgin);
  SAVE_UINT32(self, vminfop, pgout);
  SAVE_UINT32(self, vminfop, pgpgout);
  SAVE_UINT32(self, vminfop, swapin);
  SAVE_UINT32(self, vminfop, pgswapin);
  SAVE_UINT32(self, vminfop, swapout);
  SAVE_UINT32(self, vminfop, pgswapout);
  SAVE_UINT32(self, vminfop, zfod);
  SAVE_UINT32(self, vminfop, dfree);
  SAVE_UINT32(self, vminfop, scan);
  SAVE_UINT32(self, vminfop, rev);
  SAVE_UINT32(self, vminfop, hat_fault);
  SAVE_UINT32(self, vminfop, as_fault);
  SAVE_UINT32(self, vminfop, maj_fault);
  SAVE_UINT32(self, vminfop, cow_fault);
  SAVE_UINT32(self, vminfop, prot_fault);
  SAVE_UINT32(self, vminfop, softlock);
  SAVE_UINT32(self, vminfop, kernel_asflt);
  SAVE_UINT32(self, vminfop, pgrrun);
  SAVE_UINT32(self, vminfop, execpgin);
  SAVE_UINT32(self, vminfop, execpgout);
  SAVE_UINT32(self, vminfop, execfree);
  SAVE_UINT32(self, vminfop, anonpgin);
  SAVE_UINT32(self, vminfop, anonpgout);
  SAVE_UINT32(self, vminfop, anonfree);
  SAVE_UINT32(self, vminfop, fspgin);
  SAVE_UINT32(self, vminfop, fspgout);
  SAVE_UINT32(self, vminfop, fsfree);
}

/*
 * Definitions in /usr/include/sys/var.h
 */

static void
save_var(HV *self, kstat_t *kp, int strip_str)
{
  struct var *varp;

  /* PERL_ASSERT(kp->ks_ndata == 1); */
  PERL_ASSERT(kp->ks_data_size == sizeof (struct var));
  varp = (struct var *)(kp->ks_data);

  SAVE_INT32(self, varp, v_buf);
  SAVE_INT32(self, varp, v_call);
  SAVE_INT32(self, varp, v_proc);
  SAVE_INT32(self, varp, v_maxupttl);
  SAVE_INT32(self, varp, v_nglobpris);
  SAVE_INT32(self, varp, v_maxsyspri);
  SAVE_INT32(self, varp, v_clist);
  SAVE_INT32(self, varp, v_maxup);
  SAVE_INT32(self, varp, v_hbuf);
  SAVE_INT32(self, varp, v_hmask);
  SAVE_INT32(self, varp, v_pbuf);
  SAVE_INT32(self, varp, v_sptmap);
  SAVE_INT32(self, varp, v_maxpmem);
  SAVE_INT32(self, varp, v_autoup);
  SAVE_INT32(self, varp, v_bufhwm);
}

/*
 * Definition in  /usr/include/sys/sysinfo.h
 */

static void
save_sysinfo(HV *self, kstat_t *kp, int strip_str)
{
  sysinfo_t *sysinfop;

  /* PERL_ASSERT(kp->ks_ndata == 1); */
  PERL_ASSERT(kp->ks_data_size == sizeof (sysinfo_t));
  sysinfop = (sysinfo_t *)(kp->ks_data);

  SAVE_UINT32(self, sysinfop, updates);
  SAVE_UINT32(self, sysinfop, runque);
  SAVE_UINT32(self, sysinfop, runocc);
  SAVE_UINT32(self, sysinfop, swpque);
  SAVE_UINT32(self, sysinfop, swpocc);
  SAVE_UINT32(self, sysinfop, waiting);
}

/*
 * Definition in  /usr/include/sys/sysinfo.h
 */

static void
save_vminfo(HV *self, kstat_t *kp, int strip_str)
{
  vminfo_t *vminfop;

  /* PERL_ASSERT(kp->ks_ndata == 1); */
  PERL_ASSERT(kp->ks_data_size == sizeof (vminfo_t));
  vminfop = (vminfo_t *)(kp->ks_data);

  SAVE_UINT64(self, vminfop, freemem);
  SAVE_UINT64(self, vminfop, swap_resv);
  SAVE_UINT64(self, vminfop, swap_alloc);
  SAVE_UINT64(self, vminfop, swap_avail);
  SAVE_UINT64(self, vminfop, swap_free);
  SAVE_UINT64(self, vminfop, updates);
}


/*
 * We need to be able to find the function corresponding to a particular raw
 * kstat.  To do this we ignore the instance and glue the module and name
 * together to form a composite key.  We can then use the data in the kstat
 * structure to find the appropriate function.  We use a perl hash to manage the
 * lookup, where the key is "module:name" and the value is a pointer to the
 * appropriate C function.
 *
 * Note that some kstats include the instance number as part of the module
 * and/or name.  This could be construed as a bug.  However, to work around this
 * we omit any digits from the module and name as we build the table in
 * build_raw_kstat_loopup(), and we remove any digits from the module and name
 * when we look up the functions in lookup_raw_kstat_fn()
 */

/*
 * This function is called when the XS is first dlopen()ed, and builds the
 * lookup table as described above.
 */

static void
build_raw_kstat_lookup()
{
  /* Create new hash */
  raw_kstat_lookup = newHV();

  SAVE_FNP(raw_kstat_lookup, save_cpu_stat, "cpu_stat:cpu_stat");
  SAVE_FNP(raw_kstat_lookup, save_var, "unix:var");
  SAVE_FNP(raw_kstat_lookup, save_sysinfo, "unix:sysinfo");
  SAVE_FNP(raw_kstat_lookup, save_vminfo, "unix:vminfo");
/*
  SAVE_FNP(raw_kstat_lookup, save_nfs, "nfs:mntinfo");
 */
#ifdef __sparc
/*
  SAVE_FNP(raw_kstat_lookup, save_sfmmu_global_stat,
      "unix:sfmmu_global_stat");
  SAVE_FNP(raw_kstat_lookup, save_sfmmu_tsbsize_stat,
      "unix:sfmmu_tsbsize_stat");
  SAVE_FNP(raw_kstat_lookup, save_simmstat, "unix:simm-status");
  SAVE_FNP(raw_kstat_lookup, save_temperature, "unix:temperature");
  SAVE_FNP(raw_kstat_lookup, save_temp_over, "unix:temperature override");
  SAVE_FNP(raw_kstat_lookup, save_ps_shadow, "unix:ps_shadow");
  SAVE_FNP(raw_kstat_lookup, save_fault_list, "unix:fault_list");
*/
#endif
}


/*
 * This finds and returns the raw kstat reader function corresponding to the
 * supplied module and name.  If no matching function exists, 0 is returned.
 */

static kstat_raw_reader_t lookup_raw_kstat_fn(char *module, char *name)
{
  char                  key[KSTAT_STRLEN * 2];
  register char        *f, *t;
  SV                  **entry;
  kstat_raw_reader_t    fnp;

  /* Copy across module & name, removing any digits - see comment above */
  for (f = module, t = key; *f != '\0'; f++, t++) {
    while (*f != '\0' && isdigit(*f)) { f++; }
    *t = *f;
  }
  *t++ = ':';
  for (f = name; *f != '\0'; f++, t++) {
    while (*f != '\0' && isdigit(*f)) {
      f++;
    }
    *t = *f;
  }
  *t = '\0';

  /* look up & return the function, or teturn 0 if not found */
  if ((entry = hv_fetch(raw_kstat_lookup, key, strlen(key), FALSE)) == 0)
  {
    fnp = 0;
  } else {
    fnp = (kstat_raw_reader_t)(uintptr_t)SvIV(*entry);
  }
  return (fnp);
}

/*
 * This module converts the flat list returned by kstat_read() into a perl hash
 * tree keyed on module, instance, name and statistic.  The following functions
 * provide code to create the nested hashes, and to iterate over them.
 */

/*
 * Given module, instance and name keys return a pointer to the hash tied to
 * the bottommost hash.  If the hash already exists, we just return a pointer
 * to it, otherwise we create the hash and any others also required above it in
 * the hierarchy.  The returned tiehash is blessed into the
 * Solaris::kstat::_Stat class, so that the appropriate TIEHASH methods are
 * called when the bottommost hash is accessed.  If the is_new parameter is
 * non-null it will be set to TRUE if a new tie has been created, and FALSE if
 * the tie already existed.
 */

static HV *
get_tie(SV *self, char *module, int instance, char *name, int *is_new)
{
  char str_inst[11];  /* big enough for up to 10^10 instances */
  char *key[3];       /* 3 part key: module, instance, name */
  int  k;
  int  new;
  HV   *hash;
  HV   *tie;

  /* Create the keys */
  (void) snprintf(str_inst, sizeof (str_inst), "%d", instance);
  key[0] = module;
  key[1] = str_inst;
  key[2] = name;

  /* Iteratively descend the tree, creating new hashes as required */
  hash = (HV *)SvRV(self);
  for (k = 0; k < 3; k++) {
    SV **entry;

    SvREADONLY_off(hash);
    entry = hv_fetch(hash, key[k], strlen(key[k]), TRUE);

    /* If the entry doesn't exist, create it */
    if (! SvOK(*entry)) {
      HV *newhash;
      SV *rv;

      newhash = newHV();
      rv = newRV_noinc((SV *)newhash);
      sv_setsv(*entry, rv);
      SvREFCNT_dec(rv);
      if (k < 2) {
        SvREADONLY_on(newhash);
      }
      SvREADONLY_on(*entry);
      SvREADONLY_on(hash);
      hash = newhash;
      new = 1;

      /* Otherwise it already existed */
    } else {
      SvREADONLY_on(hash);
      hash = (HV *)SvRV(*entry);
      new = 0;
    }
  }

  /* Create and bless a hash for the tie, if necessary */
  if (new) {
    SV *tieref;
    HV *stash;

    tie = newHV();
    tieref = newRV_noinc((SV *)tie);
    if (SvREFCNT(tieref) > 1) {
      warn("just after newRV_noinc(), tieref REFCNT too high\n");
    }
    stash = gv_stashpv("Solaris::kstat::_Stat", GV_ADD);
    sv_bless(tieref, stash);
    if (SvREFCNT(tieref) > 1) {
      warn("just after sv_bless(), tieref REFCNT too high\n");
    }

    /* Add TIEHASH magic */
    hv_magic(hash, (GV *)tieref, PERL_MAGIC_tied );
    /*
    if (SvREFCNT(tieref) > 1) {
      warn("just after hv_magic(), tieref REFCNT too high\n");
    }
    */
    /* Why do we have to decrement the reference count here??? */
    SvREFCNT_dec(tieref);

    SvREADONLY_on(hash);

    /* Otherwise, just find the existing tied hash */
  } else {
    MAGIC *mg;

    mg = mg_find((SV *)hash, 'P');
    PERL_ASSERTMSG(mg != 0, "get_tie: lost P magic");
    tie = (HV *)SvRV(mg->mg_obj);
  }
  if (is_new) {
    *is_new = new;
  }
  return (tie);
}

/*
 * This is an iterator function used to traverse the hash hierarchy and apply
 * the passed function to the tied hashes at the bottom of the hierarchy.  If
 * any of the callback functions return 0, 0 is returned, otherwise 1
 */

  static int
apply_to_ties(SV *self, ATTCb_t cb, void *arg)
{
  HV   *hash1;
  HE   *entry1;
  int   ret;

  hash1 = (HV *)SvRV(self);
  hv_iterinit(hash1);
  ret = 1;

  /* Iterate over each module */
  while ((entry1 = hv_iternext(hash1))) {
    HV *hash2;
    HE *entry2;

    hash2 = (HV *)SvRV(hv_iterval(hash1, entry1));
    hv_iterinit(hash2);

    /* Iterate over each module:instance */
    while ((entry2 = hv_iternext(hash2))) {
      HV *hash3;
      HE *entry3;

      hash3 = (HV *)SvRV(hv_iterval(hash2, entry2));
      hv_iterinit(hash3);

      /* Iterate over each module:instance:name */
      while ((entry3 = hv_iternext(hash3))) {
        HV    *hash4;
        MAGIC *mg;

        /* Get the tie */
        hash4 = (HV *)SvRV(hv_iterval(hash3, entry3));
        mg = mg_find((SV *)hash4, 'P');
        PERL_ASSERTMSG(mg != 0,
            "apply_to_ties: lost P magic");

        /* Apply the callback */
        if (! cb((HV *)SvRV(mg->mg_obj), arg)) {
          ret = 0;
        }
      }
    }
  }
  return (ret);
}

/*
 * Mark this HV as valid - used by update() when pruning deleted kstat nodes
 */

  static int
set_valid(HV *self, void *arg)
{
  MAGIC *mg;

  mg = mg_find((SV *)self, '~');
  PERL_ASSERTMSG(mg != 0, "set_valid: lost ~ magic");
  ((KstatInfo_t *)SvPVX(mg->mg_obj))->valid = (int)(intptr_t)arg;
  return (1);
}

/*
 * Prune invalid kstat nodes. This is called when kstat_chain_update() detects
 * that the kstat chain has been updated.  This removes any hash tree entries
 * that no longer have a corresponding kstat.  If del is non-null it will be
 * set to the keys of the deleted kstat nodes, if any.  If any entries are
 * deleted 1 will be retured, otherwise 0
 */

  static int
prune_invalid(SV *self, AV *del)
{
  HV      *hash1;
  HE      *entry1;
  STRLEN   klen;
  char    *module, *instance, *name, *key;
  int      ret;

  hash1 = (HV *)SvRV(self);
  hv_iterinit(hash1);
  ret = 0;

  /* Iterate over each module */
  while ((entry1 = hv_iternext(hash1))) {
    HV *hash2;
    HE *entry2;

    module = HePV(entry1, PL_na);
    hash2 = (HV *)SvRV(hv_iterval(hash1, entry1));
    hv_iterinit(hash2);

    /* Iterate over each module:instance */
    while ((entry2 = hv_iternext(hash2))) {
      HV *hash3;
      HE *entry3;

      instance = HePV(entry2, PL_na);
      hash3 = (HV *)SvRV(hv_iterval(hash2, entry2));
      hv_iterinit(hash3);

      /* Iterate over each module:instance:name */
      while ((entry3 = hv_iternext(hash3))) {
        HV    *hash4;
        MAGIC *mg;
        HV    *tie;

        name = HePV(entry3, PL_na);
        hash4 = (HV *)SvRV(hv_iterval(hash3, entry3));
        mg = mg_find((SV *)hash4, 'P');
        PERL_ASSERTMSG(mg != 0,
            "prune_invalid: lost P magic");
        tie = (HV *)SvRV(mg->mg_obj);
        mg = mg_find((SV *)tie, '~');
        PERL_ASSERTMSG(mg != 0,
            "prune_invalid: lost ~ magic");

        /* If this is marked as invalid, prune it */
        if (((KstatInfo_t *)SvPVX(
                (SV *)mg->mg_obj))->valid == FALSE) {
          SvREADONLY_off(hash3);
          key = HePV(entry3, klen);
          hv_delete(hash3, key, klen, G_DISCARD);
          SvREADONLY_on(hash3);
          if (del) {
            av_push(del,
                newSVpvf("%s:%s:%s",
                  module, instance, name));
          }
          ret = 1;
        }
      }

      /* If the module:instance:name hash is empty prune it */
      if (HvKEYS(hash3) == 0) {
        SvREADONLY_off(hash2);
        key = HePV(entry2, klen);
        hv_delete(hash2, key, klen, G_DISCARD);
        SvREADONLY_on(hash2);
      }
    }
    /* If the module:instance hash is empty prune it */
    if (HvKEYS(hash2) == 0) {
      SvREADONLY_off(hash1);
      key = HePV(entry1, klen);
      hv_delete(hash1, key, klen, G_DISCARD);
      SvREADONLY_on(hash1);
    }
  }
  return (ret);
}

/*
 * Named kstats are returned as a list of key/values.  This function converts
 * such a list into the equivalent perl datatypes, and stores them in the passed
 * hash.
 */

static void
save_named(HV *self, kstat_t *kp, int strip_str)
{
  kstat_named_t *knp;
  int            n;
  SV*            value;

  for (n = kp->ks_ndata, knp = KSTAT_NAMED_PTR(kp); n > 0; n--, knp++) {
    switch (knp->data_type) {
    case KSTAT_DATA_CHAR:
      value = newSVpv(knp->value.c, strip_str ?
          strlen(knp->value.c) : sizeof (knp->value.c));
      break;
    case KSTAT_DATA_INT32:
      value = newSViv(knp->value.i32);
      break;
    case KSTAT_DATA_UINT32:
      value = NEW_UV(knp->value.ui32);
      break;
    case KSTAT_DATA_INT64:
      value = NEW_UV(knp->value.i64);
      break;
    case KSTAT_DATA_UINT64:
      value = NEW_UV(knp->value.ui64);
      break;
    case KSTAT_DATA_STRING:
      if (KSTAT_NAMED_STR_PTR(knp) == NULL)
        value = newSVpv("null", sizeof ("null") - 1);
      else
        value = newSVpv(KSTAT_NAMED_STR_PTR(knp),
            KSTAT_NAMED_STR_BUFLEN(knp) -1);
      break;
    default:
      PERL_ASSERTMSG(0, "kstat_read: invalid data type");
      continue;
    }
    if (hv_store(self, knp->name, strlen(knp->name), value, 0) == NULL) {
      warn("hv_store returns NULL at %d of %s (function %s)\n",
           __FILE__, __LINE__, __func__);
    }
  }
}

/*
 * Read kstats and copy into the supplied perl hash structure.  If refresh is
 * true, this function is being called as part of the update() method.  In this
 * case it is only necessary to read the kstats if they have previously been
 * accessed (kip->read == TRUE).  If refresh is false, this function is being
 * called prior to returning a value to the caller. In this case, it is only
 * necessary to read the kstats if they have not previously been read.  If the
 * kstat_read() fails, 0 is returned, otherwise 1
 */

static int
read_kstats(HV *self, int refresh)
{
  MAGIC              *mg;
  KstatInfo_t        *kip;
  kstat_raw_reader_t  fnp;

  /* Find the MAGIC KstatInfo_t data structure */
  mg = mg_find((SV *)self, '~');
  PERL_ASSERTMSG(mg != 0, "read_kstats: lost ~ magic");
  kip = (KstatInfo_t *)SvPVX(mg->mg_obj);

  /* Return early if we don't need to actually read the kstats */
  if ((refresh && ! kip->read) || (! refresh && kip->read)) {
    return (1);
  }

  /* Read the kstats and return 0 if this fails */
  if (kstat_read(kip->kstat_ctl, kip->kstat, NULL) < 0) {
    return (0);
  }

  /* Save the read data */
  if (hv_store(self, "snaptime", 8, NEW_HRTIME(kip->kstat->ks_snaptime), 0) == NULL) {
    warn("hv_store returns NULL at %d of %s (function %s)\n",
         __FILE__, __LINE__, __func__);
  }
  switch (kip->kstat->ks_type) {
    case KSTAT_TYPE_RAW:
      if ((fnp = lookup_raw_kstat_fn(kip->kstat->ks_module,
                                     kip->kstat->ks_name)) != 0) {
        fnp(self, kip->kstat, kip->strip_str);
      }
      break;
    case KSTAT_TYPE_NAMED:
      save_named(self, kip->kstat, kip->strip_str);
      break;
    case KSTAT_TYPE_INTR:
      /* save_intr(self, kip->kstat, kip->strip_str); */
      break;
    case KSTAT_TYPE_IO:
      /* save_io(self, kip->kstat, kip->strip_str); */
      break;
    case KSTAT_TYPE_TIMER:
      /* save_timer(self, kip->kstat, kip->strip_str); */
      break;
    default:
      PERL_ASSERTMSG(0, "read_kstats: illegal kstat type");
      break;
  }
  kip->read = TRUE;
  return (1);
}

/*
 * The XS code exported to perl is below here.  Note that the XS preprocessor
 * has its own commenting syntax, so all comments from this point on are in
 * that form.
 */

/* The following XS methods are the ABI of the Sun::Solaris::Kstat package */

MODULE = Solaris::kstat       PACKAGE = Solaris::kstat
PROTOTYPES: ENABLE

# Create the raw kstat to store function lookup table on load
BOOT:
  build_raw_kstat_lookup();

#
# The Solaris::kstat constructor.  This builds the nested
# name:instance:module hash structure, but doesn't actually read the
# underlying kstats.  This is done on demand by the TIEHASH methods in
# Solaris:kstat::_Stat
#

SV*
new(class, ...)
  char *class;
PREINIT:
  HV          *stash;
  kstat_ctl_t *kc;
  SV          *kcsv;
  kstat_t     *kp;
  KstatInfo_t kstatinfo;
  int         sp, strip_str;
CODE:
  /* Check we have an even number of arguments, excluding the class */
  sp = 1;
  if (((items - sp) % 2) != 0) {
    croak(DEBUG_ID ": new: invalid number of arguments");
  }

  /* Process any (name => value) arguments */
  strip_str = 0;
  while (sp < items) {
    SV *name, *value;

    name = ST(sp);
    sp++;
    value = ST(sp);
    sp++;
    if (strcmp(SvPVX(name), "strip_strings") == 0) {
      strip_str = SvTRUE(value);
    } else {
      croak(DEBUG_ID ": new: invalid parameter name '%s'",
          SvPVX(name));
    }
  }

  /* Open the kstats handle */
  if ((kc = kstat_open()) == 0) {
    XSRETURN_UNDEF;
  }

  /* Create a blessed hash ref */
  RETVAL = (SV *)newRV_noinc((SV *)newHV());
  stash = gv_stashpv(class, TRUE);
  sv_bless(RETVAL, stash);

  /* Create a place to save the KstatInfo_t structure */
  kcsv = newSVpv((char *)&kc, sizeof (kc));
  sv_magic(SvRV(RETVAL), kcsv, '~', 0, 0);
  SvREFCNT_dec(kcsv);

  /* Initialise the KstatsInfo_t structure */
  kstatinfo.read = FALSE;
  kstatinfo.valid = TRUE;
  kstatinfo.strip_str = strip_str;
  kstatinfo.kstat_ctl = kc;

  /* Scan the kstat chain, building hash entries for the kstats */
  for (kp = kc->kc_chain; kp != 0; kp = kp->ks_next) {
    HV *tie;
    SV *kstatsv;

    /* Don't bother storing the kstat headers */
    if (strncmp(kp->ks_name, "kstat_", 6) == 0) {
      continue;
    }

    /* Don't bother storing raw stats we don't understand */
    if (kp->ks_type == KSTAT_TYPE_RAW &&
        lookup_raw_kstat_fn(kp->ks_module, kp->ks_name) == 0) {
#ifdef REPORT_UNKNOWN
      (void)fprintf(stderr,
                    "Unknown kstat type %s:%d:%s - %d of size %d\n",
                    kp->ks_module, kp->ks_instance, kp->ks_name,
                    kp->ks_ndata, kp->ks_data_size);
#endif
      continue;
    }

    /* Create a 3-layer hash hierarchy - module.instance.name */
    tie = get_tie(RETVAL, kp->ks_module, kp->ks_instance,
                          kp->ks_name, 0);

    /* Save the data necessary to read the kstat info on demand */
    if (hv_store(tie, "class", 5, newSVpv(kp->ks_class, 0), 0) == NULL) {
      warn("hv_store returns NULL at %d of %s (function %s)\n",
           __FILE__, __LINE__, __func__);
    }
    if (hv_store(tie, "crtime", 6, NEW_HRTIME(kp->ks_crtime), 0) == NULL) {
      warn("hv_store returns NULL at %d of %s (function %s)\n",
           __FILE__, __LINE__, __func__);
    }
    kstatinfo.kstat = kp;
    kstatsv = newSVpv((char *)&kstatinfo, sizeof (kstatinfo));
    sv_magic((SV *)tie, kstatsv, '~', 0, 0);
    SvREFCNT_dec(kstatsv);
  }
  SvREADONLY_on(SvRV(RETVAL));
OUTPUT:
  RETVAL

 #
 # Update the perl hash structure so that it is in line with the kernel kstats
 # data.  Only kstats athat have previously been accessed are read,
 #

 # Scalar context: true/false
 # Array context: (\@added, \@deleted)
void
update(self)
  SV* self;
PREINIT:
  MAGIC       *mg;
  kstat_ctl_t *kc;
  kstat_t     *kp;
  int          ret;
  AV          *add, *del;
PPCODE:
  /* Find the hidden KstatInfo_t structure */
  mg = mg_find(SvRV(self), '~');
  PERL_ASSERTMSG(mg != 0, "update: lost ~ magic");
  kc = *(kstat_ctl_t **)SvPVX(mg->mg_obj);
  
  /* Update the kstat chain, and return immediately on error. */
  if ((ret = kstat_chain_update(kc)) == -1) {
    if (GIMME_V == G_ARRAY) {
      EXTEND(SP, 2);
      PUSHs(sv_newmortal());
      PUSHs(sv_newmortal());
    } else {
      EXTEND(SP, 1);
      PUSHs(sv_2mortal(newSViv(ret)));
    }
  }
  
  /* Create the arrays to be returned if in an array context */
  if (GIMME_V == G_ARRAY) {
    add = newAV();
    del = newAV();
  } else {
    add = 0;
    del = 0;
  }
  
  /*
   * If the kstat chain hasn't changed we can just reread any stats
   * that have already been read
   */
  if (ret == 0) {
    if (! apply_to_ties(self, (ATTCb_t)read_kstats, (void *)TRUE)) {
      if (GIMME_V == G_ARRAY) {
        EXTEND(SP, 2);
        PUSHs(sv_2mortal(newRV_noinc((SV *)add)));
        PUSHs(sv_2mortal(newRV_noinc((SV *)del)));
      } else {
        EXTEND(SP, 1);
        PUSHs(sv_2mortal(newSViv(-1)));
      }
    }
  
    /*
     * Otherwise we have to update the Perl structure so that it is in
     * agreement with the new kstat chain.  We do this in such a way as to
     * retain all the existing structures, just adding or deleting the
     * bare minimum.
     */
  } else {
    KstatInfo_t kstatinfo;
  
    /*
     * Step 1: set the 'invalid' flag on each entry
     */
    apply_to_ties(self, &set_valid, (void *)FALSE);
  
    /*
     * Step 2: Set the 'valid' flag on all entries still in the
     * kernel kstat chain
     */
    kstatinfo.read      = FALSE;
    kstatinfo.valid     = TRUE;
    kstatinfo.kstat_ctl = kc;
    for (kp = kc->kc_chain; kp != 0; kp = kp->ks_next) {
      int  new;
      HV  *tie;
  
      /* Don't bother storing the kstat headers or types */
      if (strncmp(kp->ks_name, "kstat_", 6) == 0) {
        continue;
      }
  
      /* Don't bother storing raw stats we don't understand */
      if (kp->ks_type == KSTAT_TYPE_RAW &&
          lookup_raw_kstat_fn(kp->ks_module, kp->ks_name)
            == 0) {
  #ifdef REPORT_UNKNOWN
        (void) printf("Unknown kstat type %s:%d:%s "
            "- %d of size %d\n", kp->ks_module,
            kp->ks_instance, kp->ks_name,
            kp->ks_ndata, kp->ks_data_size);
  #endif
        continue;
      }
  
      /* Find the tied hash associated with the kstat entry */
      tie = get_tie(self, kp->ks_module, kp->ks_instance,
          kp->ks_name, &new);
  
      /* If newly created store the associated kstat info */
      if (new) {
        SV *kstatsv;
  
        /*
         * Save the data necessary to read the kstat
         * info on demand
         */
        if (hv_store(tie, "class", 5,
                     newSVpv(kp->ks_class, 0), 0) == NULL) {
          warn("hv_store of class returns NULL");
        }
        if (hv_store(tie, "crtime", 6,
                     NEW_HRTIME(kp->ks_crtime), 0) == NULL) {
          /* This seems to cause a core dump */
          /*
          warn("hv_store returns NULL at %d of %s (function %s)\n",
               __FILE__, __LINE__, __func__);
          */
          warn("hv_store of crtime returns NULL");
        }
        kstatinfo.kstat = kp;
        kstatsv = newSVpv((char *)&kstatinfo,
            sizeof (kstatinfo));
        sv_magic((SV *)tie, kstatsv, '~', 0, 0);
        SvREFCNT_dec(kstatsv);
  
        /* Save the key on the add list, if required */
        if (GIMME_V == G_ARRAY) {
          av_push(add, newSVpvf("%s:%d:%s",
                kp->ks_module, kp->ks_instance,
                kp->ks_name));
        }
  
        /* If the stats already exist, just update them */
      } else {
        MAGIC *mg;
        KstatInfo_t *kip;
  
        /* Find the hidden KstatInfo_t */
        mg = mg_find((SV *)tie, '~');
        PERL_ASSERTMSG(mg != 0, "update: lost ~ magic");
        kip = (KstatInfo_t *)SvPVX(mg->mg_obj);
  
        /* Mark the tie as valid */
        kip->valid = TRUE;
  
        /* Re-save the kstat_t pointer.  If the kstat
         * has been deleted and re-added since the last
         * update, the address of the kstat structure
         * will have changed, even though the kstat will
         * still live at the same place in the perl
         * hash tree structure.
         */
        kip->kstat = kp;
  
        /* Reread the stats, if read previously */
        read_kstats(tie, TRUE);
      }
    }
  
    /*
     *Step 3: Delete any entries still marked as 'invalid'
     */
    ret = prune_invalid(self, del);
  
  }
  if (GIMME_V == G_ARRAY) {
    EXTEND(SP, 2);
    PUSHs(sv_2mortal(newRV_noinc((SV *)add)));
    PUSHs(sv_2mortal(newRV_noinc((SV *)del)));
  } else {
    EXTEND(SP, 1);
    PUSHs(sv_2mortal(newSViv(ret)));
  }

#
# gethrtime() Utility Function
#
hrtime_t
gethrtime(void)
CODE:
  RETVAL = gethrtime();
OUTPUT:
  RETVAL

#
# Destructor.  Closes the kstat connection
#

void
DESTROY(self)
  SV *self;
PREINIT:
  MAGIC       *mg;
  kstat_ctl_t *kc;
CODE:
  mg = mg_find(SvRV(self), '~');
  PERL_ASSERTMSG(mg != 0, "DESTROY: lost ~ magic");
  kc = *(kstat_ctl_t **)SvPVX(mg->mg_obj);
  if (kstat_close(kc) != 0) {
    croak(DEBUG_ID ": kstat_close: failed with errno %d", errno);
  }

#
# The following XS methods implement the TIEHASH mechanism used to update the
# kstats hash structure.  These are blessed into a package that isn't
# visible to callers of the Solaris::kstat module
#

MODULE = Solaris::kstat PACKAGE = Solaris::kstat::_Stat
PROTOTYPES: ENABLE

#
# If a value has already been read, return it.  Otherwise read the appropriate
# kstat and then return the value
#

SV*
FETCH(self, key)
  SV* self;
  SV* key;
PREINIT:
  char    *k;
  STRLEN   klen;
  SV     **value;
CODE:
  self = SvRV(self);
  k = SvPV(key, klen);
  if (strNE(k, "class") && strNE(k, "crtime")) {
    read_kstats((HV *)self, FALSE);
  }
  value = hv_fetch((HV *)self, k, klen, FALSE);
  if (value) {
    RETVAL = *value; SvREFCNT_inc(RETVAL);
  } else {
    RETVAL = &PL_sv_undef;
  }
OUTPUT:
  RETVAL

#
# Save the passed value into the kstat hash.  Read the appropriate kstat first,
# only when necessary.  Note that this DOES NOT update the underlying kernel kstat
# structure.
#

SV*
STORE(self, key, value)
  SV* self;
  SV* key;
  SV* value;
PREINIT:
  char  *k;
  STRLEN  klen;
CODE:
  self = SvRV(self);
  k = SvPV(key, klen);
  if (strNE(k, "class") && strNE(k, "crtime")) {
    read_kstats((HV *)self, FALSE);
  }
  SvREFCNT_inc(value);
  RETVAL = *(hv_store((HV *)self, k, klen, value, 0));
  SvREFCNT_inc(RETVAL);
OUTPUT:
  RETVAL

#
# Check for the existence of the passed key.  Read the kstat first if necessary
#

bool
EXISTS(self, key)
  SV* self;
  SV* key;
PREINIT:
  char *k;
CODE:
  self = SvRV(self);
  k = SvPV(key, PL_na);
  if (strNE(k, "class") && strNE(k, "crtime")) {
    read_kstats((HV *)self, FALSE);
  }
  RETVAL = hv_exists_ent((HV *)self, key, 0);
OUTPUT:
  RETVAL

#
# Hash iterator initialisation.  Read the kstats if necessary.
#

SV*
FIRSTKEY(self)
  SV* self;
PREINIT:
  HE *he;
PPCODE:
  self = SvRV(self);
  read_kstats((HV *)self, FALSE);
  hv_iterinit((HV *)self);
  if ((he = hv_iternext((HV *)self))) {
    EXTEND(SP, 1);
    PUSHs(hv_iterkeysv(he));
  }

#
# Return hash iterator next value.  Read the kstats if necessary.
#

SV*
NEXTKEY(self, lastkey)
  SV* self;
  SV* lastkey;
PREINIT:
  HE *he;
PPCODE:
  self = SvRV(self);
  if ((he = hv_iternext((HV *)self))) {
    EXTEND(SP, 1);
    PUSHs(hv_iterkeysv(he));
  }

#
# Delete the specified hash entry.
#

SV*
DELETE(self, key)
  SV *self;
  SV *key;
CODE:
  self = SvRV(self);
  RETVAL = hv_delete_ent((HV *)self, key, 0, 0);
  if (RETVAL) {
    SvREFCNT_inc(RETVAL);
  } else {
    RETVAL = &PL_sv_undef;
  }
OUTPUT:
  RETVAL

#
# Clear the entire hash.  This will stop any update() calls rereading this
# kstat until it is accessed again.
#

void
CLEAR(self)
  SV* self;
PREINIT:
  MAGIC   *mg;
  KstatInfo_t *kip;
CODE:
  self = SvRV(self);
  hv_clear((HV *)self);
  mg = mg_find(self, '~');
  PERL_ASSERTMSG(mg != 0, "CLEAR: lost ~ magic");
  kip = (KstatInfo_t *)SvPVX(mg->mg_obj);
  kip->read  = FALSE;
  kip->valid = TRUE;
  if (hv_store((HV *)self, "class", 5, newSVpv(kip->kstat->ks_class, 0), 0) == NULL) {
    warn("hv_store returns NULL at %d of %s (function %s)\n",
         __FILE__, __LINE__, __func__);
  }
  if (hv_store((HV *)self, "crtime", 6, NEW_HRTIME(kip->kstat->ks_crtime), 0) == NULL) {
    warn("hv_store returns NULL at %d of %s (function %s)\n",
         __FILE__, __LINE__, __func__);
  }
