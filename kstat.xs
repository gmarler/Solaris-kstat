/* kstat related includes */
#include <kstat.h>

/* See perlguts for explanation of this */
#define PERL_NO_GET_CONTEXT

/* Perl XS includes */
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

/* Private structure used for saving kstat info in the tied hashes */
typedef struct {
  char         read;      /* Kstat block has been read before */
  char         valid;     /* Kstat still exists in kstat chain */
  char         strip_str; /* Strip KSTAT_DATA_CHAR fields */
  kstat_ctl_t *kstat_ctl; /* Handle returned by kstat_open */
  kstat_t     *kstat;     /* Handle used by kstat_read */
} KstatInfo_t;

/* C functions */

MODULE = Solaris::kstat       PACKAGE = Solaris::kstat
PROTOTYPES: ENABLE

# XS code
