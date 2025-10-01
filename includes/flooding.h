#ifndef FLOODING_H
#define FLOODING_H

#include "packet.h"
/*
//Header for Flooding packets
typedef nx_struct FloodHeader {
    nx_uint16_t floodSrc;      // Node which originally sent the flood
    nx_uint16_t floodDest;     // The destination Node, or 0 if we want to send a broadcast
    nx_uint16_t floodSeq;      // Sequence number for this flood
    nx_uint8_t floodTTL;       // Time To Live
    nx_uint8_t floodType;      // 0 is a data/regular flood, 1 is an ACK for when we receive our flood.
} FloodHeader;*/
//We originally built an entire separate header, but because only one of these fields is actually unique to flooding,
//it's more space-efficient to just use the originalSrc field seen in Node.nc.
//This is because a redundant header would be eating up space that we could otherwise give to our payload.

// Flooding cache entry, used by each node to check for duplicate packets.
typedef struct FloodCacheEntry {
    uint16_t nodeId;        // Node that initiated the flood
    uint16_t maxSeq;        // Highest sequence number seen from this node
} FloodCacheEntry;

#define FLOOD_HEADER_SIZE sizeof(FloodHeader)
#define MAX_FLOOD_CACHE_ENTRIES 50//arbitrary

// Flood types
//#define FLOOD_TYPE_DATA 0
//#define FLOOD_TYPE_ACK  1
// We originally wanted to give flooding a type field to distinguish between data floods and ACK floods,
// but we can just use the protocol to accomplish that so it's wasteful.
#endif