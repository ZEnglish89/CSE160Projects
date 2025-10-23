#include "../../includes/packet.h"

interface Flooding{
    command void startFlood(uint16_t dest, uint8_t *payload, uint8_t length);
    command void initializeFlooding();
    command void handleFloodPacket(pack* receivedPkt, uint8_t pktLen, uint16_t senderId);
    event void floodReceived(uint16_t source, uint16_t seq, uint8_t *payload, uint8_t length);
    event void floodAckReceived(uint16_t source, uint16_t seq);
}