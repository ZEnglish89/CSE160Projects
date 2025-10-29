#ifndef FLOODING_H
#define FLOODING_H

#include "packet.h"

//Header for Flooding packets
typedef nx_struct FloodHeader {
    nx_uint16_t floodSrc;      // Node which originally sent the flood
    nx_uint16_t floodDest;     // The destination Node, or 0 if we want to send a broadcast
    nx_uint8_t floodTTL;       // Time To Live
    nx_uint16_t floodSeq;      // Sequence number for this flood
    nx_uint8_t floodType;      // 0 is a data/regular flood, 1 is an ACK for when we receive our flood.
} FloodHeader;

// Flooding cache entry
typedef struct FloodCacheEntry {
    uint16_t nodeId;        // Node that initiated the flood
    uint16_t maxSeq;        // Highest sequence number seen from this node
} FloodCacheEntry;

#define FLOOD_HEADER_SIZE sizeof(FloodHeader)
#define MAX_FLOOD_CACHE_ENTRIES 50

// Flood types
#define FLOOD_TYPE_DATA 0
#define FLOOD_TYPE_ACK  1

#endif