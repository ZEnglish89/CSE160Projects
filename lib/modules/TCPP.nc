//using the same includes as IP, and just using that interface.
//This will change drastically of course.

#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/IP.h"
#include "../../includes/TCP.h"

module TCPP{
    provides interface TCP;

    uses interface IP;


implementation{
    command void TCP.sendSegment(uint16_t destAddr, uint8_t *payld){
        return;
    }

    command void TCP.handleSegment(pack* msg, uint8_t pktLen, uint16_t senderId){
        return;
    }
}