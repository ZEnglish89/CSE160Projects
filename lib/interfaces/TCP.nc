//Largely using the IP module as a template for this, which we'll build out as we go.
#include "../../includes/packet.h"

interface IP{
    // We will of course need ways to send out a segment and handle an incoming segment.
    command void sendSegment(socket_store_t socket, uint8_t *payld,uint8_t pld_len);
//    command void handleSegment(pack* msg, uint8_t pktLen, uint16_t senderId);


    command void connect(uint16_t dest, uint16_t srcPort, uint16_t destPort);
    // Potential other functions to consider(many could probably just be if-blocks but this is a useful list): send/handle SYN,
    // open/close connection, calculateWindow, getSequenceNum, createSocket?
}