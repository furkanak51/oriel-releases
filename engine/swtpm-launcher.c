/* swtpm başlatıcısı: UTM, swtpm'i kitaplık olarak derler (swtpm.0.framework, swtpm_main). Bu küçük program
 * gerçek swtpm ile aynı komut satırını sunar: `swtpm socket [seçenekler…]`. */
#include <stdio.h>
#include <string.h>

int swtpm_main(int argc, char **argv, const char *prgname, const char *iface);

int main(int argc, char **argv)
{
    if (argc < 2 || strcmp(argv[1], "socket") != 0) {
        fprintf(stderr, "kullanım: %s socket [seçenekler]\n", argv[0]);
        return 1;
    }
    return swtpm_main(argc - 1, &argv[1], argv[0], "socket");
}
