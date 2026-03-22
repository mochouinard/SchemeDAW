#include "ringbuffer.h"
#include <string.h>

void ringbuffer_init(RingBuffer *rb) {
    memset(rb->buffer, 0, sizeof(rb->buffer));
    atomic_store(&rb->write_pos, 0);
    atomic_store(&rb->read_pos, 0);
}

int ringbuffer_write(RingBuffer *rb, const AudioCommand *cmd) {
    unsigned int wp = atomic_load_explicit(&rb->write_pos, memory_order_relaxed);
    unsigned int next_wp = (wp + 1) % RING_BUFFER_SIZE;
    unsigned int rp = atomic_load_explicit(&rb->read_pos, memory_order_acquire);

    if (next_wp == rp) {
        return 0; /* full */
    }

    rb->buffer[wp] = *cmd;
    atomic_store_explicit(&rb->write_pos, next_wp, memory_order_release);
    return 1;
}

int ringbuffer_read(RingBuffer *rb, AudioCommand *cmd) {
    unsigned int rp = atomic_load_explicit(&rb->read_pos, memory_order_relaxed);
    unsigned int wp = atomic_load_explicit(&rb->write_pos, memory_order_acquire);

    if (rp == wp) {
        return 0; /* empty */
    }

    *cmd = rb->buffer[rp];
    atomic_store_explicit(&rb->read_pos, (rp + 1) % RING_BUFFER_SIZE, memory_order_release);
    return 1;
}

unsigned int ringbuffer_available(const RingBuffer *rb) {
    unsigned int wp = atomic_load_explicit(&rb->write_pos, memory_order_acquire);
    unsigned int rp = atomic_load_explicit(&rb->read_pos, memory_order_acquire);
    return (wp - rp + RING_BUFFER_SIZE) % RING_BUFFER_SIZE;
}
