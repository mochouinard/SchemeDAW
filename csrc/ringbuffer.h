#ifndef RINGBUFFER_H
#define RINGBUFFER_H

#include <stdint.h>
#include <stdatomic.h>

/* Command types for Scheme -> Audio thread communication */
#define CMD_NOTE_ON       0x01
#define CMD_NOTE_OFF      0x02
#define CMD_SET_PARAM     0x03
#define CMD_SET_VOLUME    0x04
#define CMD_SET_PAN       0x05
#define CMD_SET_BPM       0x06
#define CMD_LOAD_SAMPLE   0x07
#define CMD_FX_PARAM      0x08
#define CMD_MUTE_TRACK    0x09
#define CMD_SOLO_TRACK    0x0A
#define CMD_ALL_NOTES_OFF 0x0B
#define CMD_SET_WAVEFORM  0x0C
#define CMD_SET_FILTER    0x0D
#define CMD_SET_ENVELOPE  0x0E

/* Fixed-size command message */
typedef struct {
    uint8_t  type;       /* command type (CMD_*) */
    uint8_t  track;      /* target track 0-15 */
    uint8_t  param1;     /* e.g. note number, param index */
    uint8_t  param2;     /* e.g. velocity 0-127 */
    float    fvalue;     /* float parameter value */
} AudioCommand;

#define RING_BUFFER_SIZE 4096

/* Single-Producer Single-Consumer lock-free ring buffer */
typedef struct {
    AudioCommand buffer[RING_BUFFER_SIZE];
    atomic_uint  write_pos;
    atomic_uint  read_pos;
} RingBuffer;

void ringbuffer_init(RingBuffer *rb);

/* Returns 1 on success, 0 if full */
int ringbuffer_write(RingBuffer *rb, const AudioCommand *cmd);

/* Returns 1 on success (cmd filled), 0 if empty */
int ringbuffer_read(RingBuffer *rb, AudioCommand *cmd);

/* Returns number of items available to read */
unsigned int ringbuffer_available(const RingBuffer *rb);

#endif /* RINGBUFFER_H */
