/* Shim libselinux dla erofs-utils (--file-contexts) - implementacja.
 *
 * Po co: mkfs.erofs potrafi wypiekac etykiety SELinux do obrazu EROFS, ale
 * opcja jest kompilowana pod HAVE_LIBSELINUX i linkowana z systemowa
 * biblioteka, ktorej nie ma ani w sandboxie, ani (pewnie) na runnerze.
 * Ten shim implementuje JEDYNA uzyta funkcjonalnosc: selabel_open na pliku
 * file_contexts + selabel_lookup z semantyka libselinux (selabel_file):
 *
 *   - wzorzec dopasowany od POCZATKU sciezki (rm_so == 0), koniec niekoty,
 *   - sposrod pasujacych wygrywa NAJDLUZSZY "stem" (literalny poczatek wzorca
 *     do pierwszego znaku metajakowego ERE); remis -> pozniejszy wiersz,
 *   - wiersze z typem pliku (-d/-f/-l/-c/-b/-p/-s) dotycza tylko tego typu.
 *
 * Te sama semantyka zwalidowano w tools/fc_fixup.py (dry-run na drzewie
 * donora: 4569/4569 plikow dopasowanych, 0 niedopasowanych, sensowne
 * konteksty: surfaceflinger_exec / system_lib_file / sepolicy_file...).
 */
#include <ctype.h>
#include <errno.h>
#include <regex.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include <selinux/label.h>

struct entry {
    char *pattern;
    regex_t re;
    char *stem;      /* literalny poczatek wzorca */
    size_t stem_len;
    char *context;
    int ftype;       /* 0 = dowolny; inaczej znak typu z wiersza (-d/-f/...) */
    char *raw;
};

struct selabel_handle {
    struct entry *entries;
    size_t count;
};

#define MAX_ENTRIES 65536

static int stem_meta(int c)
{
    return !(isalnum(c) || c == '/' || c == '_' || c == '.' || c == '-');
}

static char *xstrdup(const char *s)
{
    char *p = strdup(s);
    if (!p)
        abort();
    return p;
}

int is_selinux_enabled(void) { return 0; }
int freecon(char *context) { free(context); return 0; }

struct selabel_handle *selabel_open(int backend,
                                    const struct selinux_opt *opts,
                                    unsigned nopt)
{
    const char *path = NULL;
    struct selabel_handle *h;
    FILE *f;
    char line[4096];
    size_t n = 0;
    size_t used = 0;

    if (backend != SELABEL_CTX_FILE || nopt < 1) {
        errno = EINVAL;
        return NULL;
    }
    for (unsigned i = 0; i < nopt; i++) {
        if (opts[i].type == SELABEL_OPT_PATH)
            path = opts[i].value;
    }
    if (!path) {
        errno = EINVAL;
        return NULL;
    }
    f = fopen(path, "re");
    if (!f)
        return NULL;
    h = calloc(1, sizeof(*h));
    if (!h) {
        fclose(f);
        errno = ENOMEM;
        return NULL;
    }
    h->entries = calloc(MAX_ENTRIES, sizeof(struct entry));
    if (!h->entries) {
        fclose(f);
        free(h);
        errno = ENOMEM;
        return NULL;
    }
    while (fgets(line, sizeof(line), f)) {
        char *s = line, *fields[4];
        int nf = 0, ftype = 0;
        char *ctx;
        struct entry *e;

        while (isspace((unsigned char)*s))
            s++;
        if (!*s || *s == '#')
            continue;
        if (s[0] == '>' && s[1] == '>') {
            fprintf(stderr,
                    "selinux_shim: linia kontynuacji '>>' nierozpoznana "
                    "(format file_contexts nowszy niz shim) - pomijam: %.48s\n",
                    s);
            continue;
        }
        for (char *tok = strtok(s, " \t\r\n"); tok && nf < 4;
             tok = strtok(NULL, " \t\r\n"))
            fields[nf++] = tok;
        if (nf == 2) {
            ctx = fields[1];
        } else if (nf >= 3 && fields[1][0] == '-' && fields[1][1] &&
                   !fields[1][2]) {
            ctx = fields[2];
            ftype = (unsigned char)fields[1][1];
        } else {
            continue;
        }
        if (used >= MAX_ENTRIES)
            break;
        e = &h->entries[used];
        memset(e, 0, sizeof(*e));
        if (fields[0][0] == '^')
            fields[0]++;
        e->pattern = xstrdup(fields[0]);
        e->context = xstrdup(ctx);
        e->ftype = ftype;
        e->raw = xstrdup(fields[0]);
        if (regcomp(&e->re, e->pattern, REG_EXTENDED) != 0) {
            free(e->pattern);
            free(e->context);
            free(e->raw);
            continue;
        }
        e->stem_len = 0;
        while (e->pattern[e->stem_len] && !stem_meta((unsigned char)e->pattern[e->stem_len]))
            e->stem_len++;
        used++;
        n++;
    }
    fclose(f);
    h->count = used;
    fprintf(stderr, "selinux_shim: %zu wpisow kontekstowych z %s\n", n, path);
    return h;
}

void selabel_close(struct selabel_handle *hnd)
{
    if (!hnd)
        return;
    for (size_t i = 0; i < hnd->count; i++) {
        struct entry *e = &hnd->entries[i];
        regfree(&e->re);
        free(e->pattern);
        free(e->context);
        free(e->raw);
    }
    free(hnd->entries);
    free(hnd);
}

static struct entry *best_match(struct selabel_handle *h, const char *key,
                                int mode)
{
    struct entry *best = NULL;
    size_t best_stem = 0;
    int want_type = 0;

    if (S_ISDIR(mode))
        want_type = 'd';
    else if (S_ISLNK(mode))
        want_type = 'l';
    else if (S_ISREG(mode))
        want_type = 'f';
    else if (S_ISCHR(mode))
        want_type = 'c';
    else if (S_ISBLK(mode))
        want_type = 'b';
    else if (S_ISFIFO(mode))
        want_type = 'p';
    else if (S_ISSOCK(mode))
        want_type = 's';

    for (size_t i = 0; i < h->count; i++) {
        struct entry *e = &h->entries[i];
        regmatch_t pm[1];

        if (e->ftype && e->ftype != want_type)
            continue;
        if (regexec(&e->re, key, 1, pm, 0) != 0)
            continue;
        if (pm[0].rm_so != 0)
            continue; /* dopasowanie w srodku sciezki - nie liczy sie */
        if (!best || e->stem_len >= best_stem) {
            best = e;
            best_stem = e->stem_len;
        }
    }
    return best;
}

int selabel_lookup(struct selabel_handle *hnd, char **context,
                   const char *key, int type)
{
    struct entry *e;

    if (!hnd || !context || !key) {
        errno = EINVAL;
        return -1;
    }
    e = best_match(hnd, key, type);
    if (!e) {
        errno = ENOENT;
        return -1;
    }
    *context = xstrdup(e->context);
    return 0;
}

int selabel_xattr(struct selabel_handle *hnd, const char *key,
                  char **context, int *type)
{
    (void)type;
    return selabel_lookup(hnd, context, key, S_IFREG);
}
