//start off with the same includes as Flooding and LinkState, can add more when we decide we need them.
//can't imagine we will.
#include "../../includes/packet.h"

interface IP{
    //we're doing basically just one thing here, and that's checking where to forward things to,
    //packing them up properly, and sending them off.
    command void sendMessage(uint16_t destAddr, uint8_t *payld);
    command void handleMessage(pack* msg, uint8_t pktLen, uint16_t senderId);
}