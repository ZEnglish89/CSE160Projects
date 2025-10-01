#ifndef FLOODING_H
#define FLOODING_H

#include "packet.h"

// Flooding Header Structure - will be embedded in packet payload
typedef nx_struct FloodHeader {
    nx_uint16_t floodSrc;      // Source of the flood initiator
    nx_uint16_t floodDest;     // Destination node (0 for broadcast)
    nx_uint16_t floodSeq;      // Sequence number for this flood
    nx_uint8_t floodTTL;       // TTL to prevent infinite loops
    nx_uint8_t floodType;      // 0 = data flood, 1 = ACK flood
} FloodHeader;

// Flooding cache entry
typedef struct FloodCacheEntry {
    uint16_t nodeId;        // Node that initiated the flood
    uint16_t maxSeq;        // Highest sequence number seen from this node
} FloodCacheEntry;

#define FLOOD_HEADER_SIZE sizeof(FloodHeader)
#define MAX_FLOOD_CACHE_ENTRIES 50
#define FLOOD_PROTOCOL 2    // Protocol ID for flooding packets

// Flood types
#define FLOOD_TYPE_DATA 0
#define FLOOD_TYPE_ACK  1

#endif