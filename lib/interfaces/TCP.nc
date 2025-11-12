//Largely using the IP module as a template for this, which we'll build out as we go.
#include "../../includes/packet.h"

interface IP{
    // We will of course need ways to send out a segment and handle an incoming segment.
    command void sendSegment(uint16_t destAddr, uint8_t *payld);
    command void handleSegment(pack* msg, uint8_t pktLen, uint16_t senderId);

    // Potential other functions to consider(many could probably just be if-blocks but this is a useful list): send/handle SYN,
    // open/close connection, calculateWindow, getSequenceNum, createSocket?
}