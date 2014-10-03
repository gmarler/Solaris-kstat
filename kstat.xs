/* See perlguts for explanation of this */
/* #define PERL_NO_GET_CONTEXT */

/* Perl XS includes */
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

/* kstat related includes */
#include <kstat.h>

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
    newSVnv((NVTYPE) (V / 1000000000.0))

/* Private structure used for saving kstat info in the tied hashes */
typedef struct {
  char         read;      /* Kstat block has been read before */
  char         valid;     /* Kstat still exists in kstat chain */
  char         strip_str; /* Strip KSTAT_DATA_CHAR fields */
  kstat_ctl_t *kstat_ctl; /* Handle returned by kstat_open */
  kstat_t     *kstat;     /* Handle used by kstat_read */
} KstatInfo_t;

/* typedef for raw kstat reader functions */
typedef void (*kstat_raw_reader_t)(HV *, kstat_t *, int);

/* C functions */

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
    stash = gv_stashpv("Solaris::kstat::_Stat", TRUE);
    sv_bless(tieref, stash);

    /* Add TIEHASH magic */
    hv_magic(hash, (GV *)tieref, 'P');
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
    hv_store(self, knp->name, strlen(knp->name), value, 0);
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
  hv_store(self, "snaptime", 8, NEW_HRTIME(kip->kstat->ks_snaptime), 0);
  switch (kip->kstat->ks_type) {
    case KSTAT_TYPE_RAW:
    /*
      if ((fnp = lookup_raw_kstat_fn(kip->kstat->ks_module,
                                     kip->kstat->ks_name)) != 0) {
        fnp(self, kip->kstat, kip->strip_str);
      }
      */
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

# XS code
# Create the raw kstat to store function lookup table on load
#BOOT:
#  build_raw_kstat_lookup();

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
    /*
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
    */

    /* Create a 3-layer hash hierarchy - module.instance.name */
    tie = get_tie(RETVAL, kp->ks_module, kp->ks_instance,
                  kp->ks_name, 0);

    /* Save the data necessary to read the kstat info on demand */
    hv_store(tie, "class", 5, newSVpv(kp->ks_class, 0), 0);
    hv_store(tie, "crtime", 6, NEW_HRTIME(kp->ks_crtime), 0);
    kstatinfo.kstat = kp;
    kstatsv = newSVpv((char *)&kstatinfo, sizeof (kstatinfo));
    sv_magic((SV *)tie, kstatsv, '~', 0, 0);
    SvREFCNT_dec(kstatsv);
  }
  SvREADONLY_on(SvRV(RETVAL));
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
    croak(DEBUG_ID ": kstat_close: failed");
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
