/* Shim libselinux dla mkfs.erofs --file-contexts (bez systemowej libselinux).
 * Minimalny API zdefiniowane wg tego, czego realnie uzywa erofs-utils:
 * liberofs_private.h includuje <selinux/selinux.h> + <selinux/label.h> pod
 * HAVE_LIBSELINUX; wywolywane: selabel_open/lookup/close/xattr, freecon.
 */
#ifndef _SELINUX_SHIM_SELINUX_H_
#define _SELINUX_SHIM_SELINUX_H_

#include <sys/types.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

struct selinux_opt {
    int type;
    const char *value;
};

int is_selinux_enabled(void);
int freecon(char *context);

#ifdef __cplusplus
}
#endif

#endif /* _SELINUX_SHIM_SELINUX_H_ */
