/* Interpose DNS to prove IMAP module startup never resolves a hostname. */
#include <netdb.h>
#include <stdio.h>
#include <stdlib.h>

static int reject_getaddrinfo(const char *host, const char *service,
                             const struct addrinfo *hints, struct addrinfo **result)
{
    (void) service; (void) hints; (void) result;
    fprintf(stderr, "Unexpected IMAP startup DNS lookup: %s\n", host);
    exit(86);
}

__attribute__((used)) static const struct {
    const void *replacement;
    const void *original;
} interpose[] __attribute__((section("__DATA,__interpose"))) = {
    { (const void *) reject_getaddrinfo, (const void *) getaddrinfo }
};
