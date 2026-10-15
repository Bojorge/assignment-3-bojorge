#include "systemcalls.h"

#include <errno.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
#include <stdlib.h>

/**
 * @param cmd the command to execute with system()
 * @return true if the command was executed successfully,
 *         false if an error occurred or the command returned non-zero.
 */
bool do_system(const char *cmd)
{
    int ret = system(cmd);

    if (ret == -1)
    {
        return false;
    }

    if (WIFEXITED(ret) && WEXITSTATUS(ret) == 0)
    {
        return true;
    }

    return false;
}

/**
 * @param count Number of arguments, including the executable path.
 * @param ... Absolute executable path followed by its arguments.
 * @return true if the command executed successfully, false otherwise.
 */
bool do_exec(int count, ...)
{
    if (count < 1)
    {
        return false;
    }

    va_list args;
    va_start(args, count);

    char *command[count + 1];

    for (int i = 0; i < count; i++)
    {
        command[i] = va_arg(args, char *);
    }

    command[count] = NULL;
    va_end(args);

    /* Flush buffered output before creating the child process. */
    if (fflush(stdout) == EOF)
    {
        return false;
    }

    pid_t pid = fork();

    if (pid == -1)
    {
        return false;
    }

    if (pid == 0)
    {
        execv(command[0], command);

        /* Reached only if execv() fails. */
        perror("execv");
        _exit(127);
    }

    int status;
    pid_t result;

    do
    {
        result = waitpid(pid, &status, 0);
    }
    while (result == -1 && errno == EINTR);

    if (result == -1)
    {
        return false;
    }

    return WIFEXITED(status) && WEXITSTATUS(status) == 0;
}

/**
 * @param outputfile File where standard output will be redirected.
 * @param count Number of arguments, including the executable path.
 * @param ... Absolute executable path followed by its arguments.
 * @return true if the command executed successfully, false otherwise.
 */
bool do_exec_redirect(const char *outputfile, int count, ...)
{
    if (outputfile == NULL || count < 1)
    {
        return false;
    }

    va_list args;
    va_start(args, count);

    char *command[count + 1];

    for (int i = 0; i < count; i++)
    {
        command[i] = va_arg(args, char *);
    }

    command[count] = NULL;
    va_end(args);

    if (fflush(stdout) == EOF)
    {
        return false;
    }

    pid_t pid = fork();

    if (pid == -1)
    {
        return false;
    }

    if (pid == 0)
    {
        int fd = open(outputfile, O_WRONLY | O_CREAT | O_TRUNC, 0644);

        if (fd == -1)
        {
            perror("open");
            _exit(127);
        }

        if (dup2(fd, STDOUT_FILENO) == -1)
        {
            perror("dup2");
            close(fd);
            _exit(127);
        }

        close(fd);

        execv(command[0], command);

        /* Reached only if execv() fails. */
        perror("execv");
        _exit(127);
    }

    int status;
    pid_t result;

    do
    {
        result = waitpid(pid, &status, 0);
    }
    while (result == -1 && errno == EINTR);

    if (result == -1)
    {
        return false;
    }

    return WIFEXITED(status) && WEXITSTATUS(status) == 0;
}

