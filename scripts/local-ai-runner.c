// Own the model process: terminate it when Throughline exits (including crashes).
#include <sys/event.h>
#include <sys/wait.h>
#include <sys/types.h>
#include <signal.h>
#include <unistd.h>
#include <time.h>
#include <stdlib.h>
#include <errno.h>
static volatile sig_atomic_t stopping = 0;
static void stop(int sig) { (void)sig; stopping = 1; }
int main(int argc, char **argv) {
    if (argc < 2) return 64;
    pid_t owner = getppid();
    int q = kqueue(); if (q < 0) return 71;
    struct kevent change;
    EV_SET(&change, owner, EVFILT_PROC, EV_ADD, NOTE_EXIT, 0, NULL);
    if (kevent(q, &change, 1, NULL, 0, NULL) < 0 || getppid() != owner) return 71;
    signal(SIGTERM, stop); signal(SIGINT, stop);
    pid_t child = fork();
    if (child < 0) return 71;
    if (child == 0) { signal(SIGTERM, SIG_DFL); signal(SIGINT, SIG_DFL); close(q); execv(argv[1], &argv[1]); _exit(127); }
    int status = 0;
    while (!stopping) {
        pid_t result = waitpid(child, &status, WNOHANG);
        if (result == child) { close(q); return WIFEXITED(status) ? WEXITSTATUS(status) : 1; }
        if (result < 0) { if (errno == EINTR) continue; close(q); return 71; }
        struct kevent event; struct timespec timeout = {0, 200000000};
        if (kevent(q, NULL, 0, &event, 1, &timeout) > 0) stopping = 1;
        if (getppid() != owner) stopping = 1;
    }
    kill(child, SIGTERM);
    for (int i = 0; i < 30; i++) {
        if (waitpid(child, &status, WNOHANG) == child) { close(q); return 0; }
        usleep(100000);
    }
    kill(child, SIGKILL); waitpid(child, &status, 0); close(q); return 0;
}
