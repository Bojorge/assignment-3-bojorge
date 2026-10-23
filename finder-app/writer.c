#include <stdio.h>
#include <stdlib.h>
#include <syslog.h>
#include <errno.h>
#include <string.h>

int main(int argc, char *argv[])
{
    FILE *file;

    /* Se requieren exactamente dos argumentos */
    if (argc != 3) {
        fprintf(stderr, "Error: Two arguments required\n");
        return 1;
    }

    const char *writefile = argv[1];
    const char *writestr = argv[2];

    /* Inicializar syslog */
    openlog("writer", LOG_PID, LOG_USER);

    /* Registrar la operación solicitada */
    syslog(LOG_DEBUG, "Writing %s to %s", writestr, writefile);

    /* Abrir el archivo para escritura */
    file = fopen(writefile, "w");

    if (file == NULL) {
        syslog(LOG_ERR, "Error opening file %s: %s",
               writefile, strerror(errno));

        fprintf(stderr, "Error: could not open file\n");

        closelog();
        return 1;
    }

    /* Escribir el texto en el archivo */
    if (fprintf(file, "%s\n", writestr) < 0) {
        syslog(LOG_ERR, "Error writing to file %s: %s",
               writefile, strerror(errno));

        fclose(file);
        closelog();
        return 1;
    }

    /* Comprobar posibles errores al cerrar */
    if (fclose(file) != 0) {
        syslog(LOG_ERR, "Error closing file %s: %s",
               writefile, strerror(errno));

        closelog();
        return 1;
    }

    closelog();
    return 0;
}

