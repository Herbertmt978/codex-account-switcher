#ifndef SWITCHER_PLATFORM_H
#define SWITCHER_PLATFORM_H
#include <stddef.h>
#include <stdint.h>
// Platform primitives only; account policy is implemented in Swift.
uint32_t switcher_restrict_path(const char *utf8_path, int directory);
uint32_t switcher_atomic_write(const char *utf8_path, const void *bytes, size_t count);
uint32_t switcher_check_path(const char *utf8_path);
typedef struct switcher_pipe_reader switcher_pipe_reader;
typedef void (*switcher_pipe_callback)(void *context, const void *bytes, size_t count);
// The reader owns a non-inheritable duplicate of the pipe, not the supplied handle.
switcher_pipe_reader *switcher_pipe_reader_start(void *handle, switcher_pipe_callback callback, void *context);
// Cancels a blocked read and joins the reader before returning. Call only from its owner.
void switcher_pipe_reader_stop(switcher_pipe_reader *reader);
#endif
