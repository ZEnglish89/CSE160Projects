#include "../../includes/packet.h"

interface Flooding{
    command void startFlood(uint16_t dest, uint8_t *payload, uint8_t length);
    command void initializeFlooding();
    event void floodReceived(uint16_t source, uint16_t seq, uint8_t *payload, uint8_t length);
    event void floodAckReceived(uint16_t source, uint16_t seq);
}