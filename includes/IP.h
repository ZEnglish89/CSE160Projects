#ifndef IP_H
#define IP_H

#include "packet.h"

//Header for IP packets
//Basically a slimmer version of the Flooding header, because we want to
//conserve payload space but it's still useful to have a separate IPSrc and
//IPDest etc in addition to the immediate ones.
typedef nx_struct IPHeader {
    nx_uint16_t IPSrc;      // Node which originally sent the packet
    nx_uint16_t IPDest;     // The destination Node
    nx_uint8_t IPTTL;       // Time To Live
    nx_uint8_t IPProtocol;  // Protocol to use.
} IPHeader;

#define IP_HEADER_SIZE sizeof(IPHeader)

#endif