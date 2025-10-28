//start off with the same includes as Flooding, can add more when we decide we need them.
#include "../../includes/packet.h"

interface LinkState{
    command void initializeRouting();
    command void handleRoutingPacket(uint8_t* buffer, uint8_t len);
    command void startRouting();
    command void printLinkState();
    command void printRouteTable();
    
}