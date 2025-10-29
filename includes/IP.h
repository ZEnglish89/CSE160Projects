#ifndef IP_H
#define IP_H

#include "packet.h"

//Header for Flooding packets
typedef nx_struct IPHeader {
    nx_uint16_t IPSrc;      // Node which originally sent the packet
    nx_uint16_t IPDest;     // The destination Node
    nx_uint8_t IPTTL;       // Time To Live
    nx_uint8_t IPProtocol;  // Protocol to use.
} IPHeader;

#define IP_HEADER_SIZE sizeof(IPHeader)

#endif