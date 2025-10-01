#ifndef FLOODING_H
#define FLOODING_H

#include "protocol.h"

uint8_t nextSequence = 0;
uint8_t sequenceMax = 255;

int getSequence(){
    uint8_t sequenceGiven = nextSequence;
    if (nextSequence == sequenceMax){
        nextSequence = 0;
    } else {
        nextSequence++;
    }
    return sequenceGiven;
}

typedef nx_struct FloodHeader {
    nx_uint16_t floodSrc;
    nx_uint16_t floodSeq;
    nx_uint8_t floodTTL;
} FloodHeader;

typedef struct FloodCacheEntry {
    uint16_t nodeId;
    uint16_t maxSeq;
} FloodCacheEntry;

#define FLOOD_HEADER_SIZE sizeof(FloodHeader)
#define MAX_FLOOD_CACHE_ENTRIES 50
#define FLOOD_PROTOCOL 2 

#endif