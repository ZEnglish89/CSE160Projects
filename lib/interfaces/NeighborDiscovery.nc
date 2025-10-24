#include "../../includes/packet.h"

interface NeighborDiscovery{
    command void findNeighbors();
    command void printNeighbors();
    command void handleNeighborPacket(pack* myMsg,pack responseMsg,uint8_t responsePayload[14]);
    command void neighborUpdate(uint16_t nodeId);
    command uint8_t getNeighborCount();
    command uint16_t getNeighbor(uint8_t neighborIndex);
}