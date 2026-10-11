/* Shim libselinux: interfejs selabel_* (plik: label.h). */
#ifndef _SELINUX_SHIM_LABEL_H_
#define _SELINUX_SHIM_LABEL_H_

#include <selinux/selinux.h>

#ifdef __cplusplus
extern "C" {
#endif

/* wartosci dowolne - obie strony tej pary definiuje wylacznie ten shim */
#define SELABEL_CTX_FILE 0
#define SELABEL_OPT_PATH 2

struct selabel_handle;

struct selabel_handle *selabel_open(int backend,
                                    const struct selinux_opt *opts,
                                    unsigned nopt);
int selabel_lookup(struct selabel_handle *hnd, char **context,
                   const char *key, int type);
int selabel_xattr(struct selabel_handle *hnd, const char *key,
                  char **context, int *type);
void selabel_close(struct selabel_handle *hnd);

#ifdef __cplusplus
}
#endif

#endif /* _SELINUX_SHIM_LABEL_H_ */
