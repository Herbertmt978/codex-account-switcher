#ifdef _WIN32
#include "SwitcherPlatform.h"
#include <windows.h>
#include <stdlib.h>

struct switcher_pipe_reader {
    HANDLE pipe;
    HANDLE thread;
    volatile LONG stopped;
    switcher_pipe_callback callback;
    void *context;
};

static DWORD WINAPI read_pipe(void *context) {
    switcher_pipe_reader *reader = context;
    unsigned char buffer[8192];
    while (!InterlockedCompareExchange(&reader->stopped, 0, 0)) {
        DWORD count = 0;
        BOOL success = ReadFile(reader->pipe, buffer, sizeof(buffer), &count, NULL);
        if (InterlockedCompareExchange(&reader->stopped, 0, 0)) break;
        if (!success || count == 0) {
            reader->callback(reader->context, NULL, 0);
            break;
        }
        reader->callback(reader->context, buffer, count);
    }
    return 0;
}

switcher_pipe_reader *switcher_pipe_reader_start(void *handle, switcher_pipe_callback callback, void *context) {
    switcher_pipe_reader *reader = calloc(1, sizeof(*reader));
    if (!reader) return NULL;
    if (!DuplicateHandle(GetCurrentProcess(), handle, GetCurrentProcess(), &reader->pipe,
                         0, FALSE, DUPLICATE_SAME_ACCESS)) {
        free(reader);
        return NULL;
    }
    reader->callback = callback;
    reader->context = context;
    reader->thread = CreateThread(NULL, 0, read_pipe, reader, 0, NULL);
    if (!reader->thread) {
        CloseHandle(reader->pipe);
        free(reader);
        return NULL;
    }
    return reader;
}

void switcher_pipe_reader_stop(switcher_pipe_reader *reader) {
    if (!reader) return;
    InterlockedExchange(&reader->stopped, 1);
    // Repeat cancellation to cover a read beginning between the stop check and ReadFile.
    do {
        CancelSynchronousIo(reader->thread);
    } while (WaitForSingleObject(reader->thread, 1) == WAIT_TIMEOUT);
    CloseHandle(reader->thread);
    CloseHandle(reader->pipe);
    free(reader);
}
#endif
